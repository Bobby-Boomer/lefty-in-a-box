"""TTS queue and playback — ElevenLabs primary, Kokoro fallback.

Sentence queue, synthesized one at a time, played back to back, cancellable.
Half-duplex: mic is gated while mouth is speaking.
"""

import asyncio
import io
import os
import struct
import subprocess
import numpy as np
import sounddevice as sd
import httpx

import signals

# --- Configuration ---

ELEVENLABS_API_KEY = os.environ.get("ELEVENLABS_API_KEY", "")
ELEVENLABS_VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "JBFqnCBsd6RMkjVDRZzb")  # George default
ELEVENLABS_MODEL = "eleven_turbo_v2_5"
ELEVENLABS_URL = "https://api.elevenlabs.io/v1/text-to-speech"

KOKORO_URL = "http://localhost:8880/v1/audio/speech"
KOKORO_VOICE = "af_heart"

# ElevenLabs audio: mp3_44100_128, decoded locally to PCM
ELEVEN_SAMPLE_RATE = 44100
KOKORO_SAMPLE_RATE = 24000

# Where Lefty's voice goes. Empty means the system default output.
#
# Set this to a multi-output device (speakers + BlackHole) and Lefty is audible
# in the room AND on the call, without routing every other sound on the Mac into
# the call the way changing the system default would.
VOICE_OUTPUT_DEVICE = os.environ.get("VOICE_OUTPUT_DEVICE", "")


# Runtime override, so the output can change WITHOUT restarting the voice line.
# Restarting is not an option mid-call: the Claude session runs as a child of
# this process and would die with it.
#
# Two modes, switched by bin/voice-out.sh:
#   room  -> "Lefty Out" (speakers + BlackHole). Normal desk use.
#   call  -> "BlackHole 2ch". Lefty is heard ONLY through the call, so a person
#            on the call does not hear him twice — once from the room and once
#            from the call, a fraction of a second apart.
DEVICE_OVERRIDE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".voice-output-device")


def resolve_output_device(spec: str | int | None) -> int | None:
    """Resolve a device index or name substring to a sounddevice output index.

    Mirrors ears.resolve_device, but matches on output channels.
    """
    if spec is None or spec == "":
        return None
    if isinstance(spec, int) or str(spec).isdigit():
        return int(spec)
    needle = str(spec).lower()
    matches = [
        (i, d["name"])
        for i, d in enumerate(sd.query_devices())
        if d["max_output_channels"] > 0 and needle in d["name"].lower()
    ]
    if not matches:
        raise ValueError(f"No output device matching {spec!r}.")
    if len(matches) > 1:
        names = ", ".join(f"[{i}] {n}" for i, n in matches)
        raise ValueError(f"{spec!r} is ambiguous: {names}")
    return matches[0][0]


OUTPUT_DEVICE = resolve_output_device(VOICE_OUTPUT_DEVICE)


def current_output_device() -> int | None:
    """The device to play the next sentence through.

    Checked per sentence, not once at import, so `bin/voice-out.sh` can switch
    between room and call without a restart. A bad or missing override falls back
    to the startup device rather than killing playback mid-conversation.
    """
    try:
        with open(DEVICE_OVERRIDE_FILE) as f:
            name = f.read().strip()
    except FileNotFoundError:
        return OUTPUT_DEVICE
    if not name:
        return OUTPUT_DEVICE
    try:
        return resolve_output_device(name)
    except ValueError as e:
        print(f"\n[mouth] output override ignored: {e}", flush=True)
        return OUTPUT_DEVICE


class Mouth:
    def __init__(self):
        self._queue: asyncio.Queue[str | None] = asyncio.Queue()
        self._playing = False
        self._cancelled = False
        self._speaking = False
        self._http = httpx.AsyncClient(timeout=30.0)
        self._playback_task: asyncio.Task | None = None
        self._on_speaking_change = None  # callback(bool) for ducking
        # Latched off after an auth failure — a bad/unscoped key can't recover
        # mid-session, and retrying costs a round trip before every sentence.
        self._eleven_disabled = False

    @property
    def is_speaking(self) -> bool:
        return self._speaking

    def set_speaking_callback(self, cb):
        """Set callback for speaking state changes (for Spotify ducking)."""
        self._on_speaking_change = cb

    async def enqueue(self, sentence: str):
        """Add a sentence to the TTS queue."""
        await self._queue.put(sentence)

    def interrupt(self):
        """Cancel current playback and clear queue."""
        self._cancelled = True
        # Drain queue
        while not self._queue.empty():
            try:
                self._queue.get_nowait()
            except asyncio.QueueEmpty:
                break

    async def run(self):
        """Main playback loop — runs until None is enqueued."""
        while True:
            sentence = await self._queue.get()
            if sentence is None:
                break
            if self._cancelled:
                self._cancelled = False
                continue

            self._set_speaking(True)
            try:
                pcm, sample_rate = await self._synthesize(sentence)
                if pcm and not self._cancelled:
                    await self._play_pcm(pcm, sample_rate)
            except Exception as e:
                print(f"[mouth] TTS error: {e}")
            finally:
                # Only set idle if queue is empty and not cancelled
                if self._queue.empty():
                    self._set_speaking(False)
                    signals.set_state("idle")

        self._set_speaking(False)

    async def _synthesize(self, text: str) -> tuple[bytes, int]:
        """Try ElevenLabs first, fall back to Kokoro."""
        if ELEVENLABS_API_KEY and not self._eleven_disabled:
            try:
                return await self._elevenlabs_tts(text), ELEVEN_SAMPLE_RATE
            except httpx.HTTPStatusError as e:
                if e.response.status_code in (401, 403):
                    self._eleven_disabled = True
                    print(
                        f"[mouth] ElevenLabs auth rejected ({e.response.status_code}) — "
                        "using Kokoro for the rest of this session. "
                        "Check the API key's text_to_speech permission."
                    )
                else:
                    print(f"[mouth] ElevenLabs failed, falling back to Kokoro: {e}")
            except Exception as e:
                print(f"[mouth] ElevenLabs failed, falling back to Kokoro: {e}")

        try:
            return await self._kokoro_tts(text), KOKORO_SAMPLE_RATE
        except Exception as e:
            print(f"[mouth] Kokoro also failed: {e}")
            return b"", KOKORO_SAMPLE_RATE

    async def _elevenlabs_tts(self, text: str) -> bytes:
        """ElevenLabs TTS — fetch mp3_44100_128, decode with ffmpeg, master."""
        url = f"{ELEVENLABS_URL}/{ELEVENLABS_VOICE_ID}"
        resp = await self._http.post(
            url,
            headers={
                "xi-api-key": ELEVENLABS_API_KEY,
                "Content-Type": "application/json",
                "Accept": "audio/mpeg",
            },
            json={
                "text": text,
                "model_id": ELEVENLABS_MODEL,
                "voice_settings": {
                    "stability": 0.5,
                    "similarity_boost": 0.75,
                    "style": 0.0,
                },
                "output_format": "mp3_44100_128",
            },
        )
        resp.raise_for_status()
        mp3_bytes = resp.content

        # Decode mp3 + master with ffmpeg:
        # - presence boost around 3.2kHz
        # - low shelf around 140Hz
        # - gentle compression
        # - limiter
        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-i", "pipe:0",
            "-af", (
                "equalizer=f=3200:t=q:w=1.5:g=3,"       # presence boost
                "lowshelf=f=140:g=2,"                      # low shelf warmth
                "acompressor=threshold=-18dB:ratio=3:attack=5:release=50,"  # gentle compression
                "alimiter=limit=0.95:level=enabled"        # limiter
            ),
            "-f", "s16le",
            "-acodec", "pcm_s16le",
            "-ar", str(ELEVEN_SAMPLE_RATE),
            "-ac", "1",
            "pipe:1",
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        pcm_out, _ = await proc.communicate(input=mp3_bytes)
        return pcm_out

    async def _kokoro_tts(self, text: str) -> bytes:
        """Kokoro TTS — POST sentence, get raw PCM int16 24kHz mono."""
        resp = await self._http.post(
            KOKORO_URL,
            json={
                "model": "kokoro",
                "input": text,
                "voice": KOKORO_VOICE,
                "response_format": "pcm",
            },
        )
        resp.raise_for_status()
        return resp.content

    async def _teardown_stream(self, stream, loop):
        """Close an output stream without risking a CoreAudio deadlock.

        THIS IS THE HANG. Diagnosed 2026-09-18 by sampling a wedged process that
        had been stuck for 8h42m. Every single sample sat in the same place:

            stream.stop() -> PortAudio -> AudioOutputUnitStop
              -> CoreAudio -> HALB_Mutex::Lock()
                -> _pthread_mutex_firstfit_lock_slow

        A plain `stream.stop()` on macOS waits for CoreAudio's IO thread to
        finish. Called straight from the event loop thread, mid-playback, that
        can deadlock against the mutex the IO thread already holds. When it does,
        it never returns — no exception, no traceback, nothing in crash.log.
        The app just stops being alive, which is exactly what Bobby kept seeing.

        Three defences here:
          1. `abort()` when we were interrupted. It drops buffered audio instead
             of waiting for it to drain, which is what we want on a barge-in and
             is far less deadlock-prone than `stop()`.
          2. Run it in a worker thread, never on the event loop.
          3. Put a timeout on it. If CoreAudio wedges anyway we leak one thread,
             which is survivable — the voice line stays up and says so.
        """
        interrupted = self._cancelled

        def _shutdown():
            try:
                if interrupted:
                    stream.abort()
                else:
                    stream.stop()
            finally:
                stream.close()

        try:
            await asyncio.wait_for(loop.run_in_executor(None, _shutdown), timeout=5.0)
        except asyncio.TimeoutError:
            # Deliberately not re-raised. A stuck speaker must not take the
            # whole voice line with it.
            print("\n[mouth] audio stream teardown timed out after 5s — "
                  "CoreAudio is wedged. Voice line staying up.", flush=True)
        except Exception as e:
            print(f"\n[mouth] stream teardown failed: {type(e).__name__}: {e}", flush=True)

    async def _play_pcm(self, pcm_data: bytes, sample_rate: int):
        """Play PCM through speakers, feeding waveform to signal bus."""
        if not pcm_data or self._cancelled:
            return

        samples = np.frombuffer(pcm_data, dtype=np.int16)
        block_size = int(sample_rate * 0.05)  # 50ms blocks
        loop = asyncio.get_event_loop()

        stream = sd.OutputStream(
            samplerate=sample_rate,
            channels=1,
            dtype="int16",
            blocksize=block_size,
            device=current_output_device(),
        )
        stream.start()

        try:
            offset = 0
            while offset < len(samples) and not self._cancelled:
                end = min(offset + block_size, len(samples))
                block = samples[offset:end]
                stream.write(block.reshape(-1, 1))

                # Feed signal bus with this block
                signals.write_waveform(block.tobytes())

                offset = end
                # Yield to event loop
                await asyncio.sleep(0)
        finally:
            await self._teardown_stream(stream, loop)

        if self._cancelled:
            self._cancelled = False

    def _set_speaking(self, speaking: bool):
        self._speaking = speaking
        if self._on_speaking_change:
            self._on_speaking_change(speaking)

    async def close(self):
        await self._http.aclose()
