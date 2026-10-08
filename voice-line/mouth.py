"""TTS queue and playback — ElevenLabs primary, Kokoro fallback.

Sentence queue, synthesized one at a time, played back to back, cancellable.
Half-duplex: mic is gated while mouth is speaking.
"""

import asyncio
import io
import os
import struct
import time
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
# The fallback voice must not change who your agent sounds like. The old default
# `af_heart` is an American FEMALE voice, so any ElevenLabs outage silently
# swapped the agent's apparent gender mid-conversation with nothing on screen to
# say the fallback had even happened. Caught 2026-10-01. Set KOKORO_VOICE in
# .env to whatever matches your agent — `af_*` for female, `am_*` for male.
KOKORO_VOICE = os.environ.get("KOKORO_VOICE", "am_michael")

# How long to stay on Kokoro after ElevenLabs rejects us, before trying again.
# This used to be "for the rest of the session", which meant a single 401 from
# an exhausted quota stranded the agent on the fallback voice until the voice
# line was restarted — and restarting it kills the Claude session running under
# it. Topping the credits back up could not recover it. Now it heals itself.
ELEVEN_RETRY_AFTER_SECONDS = 300

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
        # One output stream, held open across sentences. See _play_pcm.
        self._stream: sd.OutputStream | None = None
        self._stream_key: tuple | None = None  # (device, sample_rate)
        # Set once CoreAudio wedges. The HAL mutex stays held for the life of
        # the process, so every later open would hang too. Stop trying.
        self._audio_wedged = False
        self._on_speaking_change = None  # callback(bool) for ducking
        # Backed off after an auth failure rather than latched off for good.
        # A bad key genuinely cannot recover, but an EXHAUSTED QUOTA returns the
        # same 401 and recovers the moment credits are topped up — so a permanent
        # latch was wrong. Holds the monotonic time to retry ElevenLabs after;
        # 0.0 means "use it now".
        self._eleven_retry_at = 0.0

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
        if ELEVENLABS_API_KEY and time.monotonic() >= self._eleven_retry_at:
            try:
                out = await self._elevenlabs_tts(text), ELEVEN_SAMPLE_RATE
                if self._eleven_retry_at:
                    print("[mouth] ElevenLabs is back — the agent's own voice is restored.")
                    self._eleven_retry_at = 0.0
                return out
            except httpx.HTTPStatusError as e:
                if e.response.status_code in (401, 403):
                    self._eleven_retry_at = time.monotonic() + ELEVEN_RETRY_AFTER_SECONDS
                    print(
                        f"[mouth] ElevenLabs auth rejected ({e.response.status_code}) — "
                        f"falling back to Kokoro ({KOKORO_VOICE}) and retrying in "
                        f"{ELEVEN_RETRY_AFTER_SECONDS}s. Usually an exhausted quota; "
                        "if it persists, check the key's text_to_speech permission."
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

    # Ceiling on any single CoreAudio call. Opening a device or writing a 50ms
    # block takes milliseconds; anything past this means CoreAudio is wedged.
    AUDIO_CALL_TIMEOUT_S = 5.0

    async def _audio_call(self, fn, what: str):
        """Run a blocking PortAudio call off the event loop, with a timeout.

        Returns True on success. On a timeout, latches _audio_wedged: the HAL
        mutex is held for good at that point, so the worker thread is leaked
        and no further audio is attempted. The event loop stays free, which
        means push-to-talk, typed input and the brain all keep working.
        """
        loop = asyncio.get_running_loop()
        try:
            await asyncio.wait_for(
                loop.run_in_executor(None, fn), timeout=self.AUDIO_CALL_TIMEOUT_S
            )
            return True
        except asyncio.TimeoutError:
            self._audio_wedged = True
            self._stream = None
            self._stream_key = None
            print(f"\n[mouth] CoreAudio wedged during {what} — voice is OFF until "
                  "the voice line is restarted. Typing still works.", flush=True)
            return False
        except Exception as e:
            print(f"\n[mouth] {what} failed: {type(e).__name__}: {e}", flush=True)
            return False

    async def _close_stream(self):
        """Close the held stream. abort(), never stop(), and never on the loop."""
        stream, self._stream, self._stream_key = self._stream, None, None
        if stream is None:
            return

        def _shutdown():
            try:
                stream.abort()
            finally:
                stream.close()

        await self._audio_call(_shutdown, "stream close")

    async def _ensure_stream(self, sample_rate: int) -> bool:
        """Have an open, started stream for this device and rate.

        THE HANG, PART TWO. Diagnosed 2026-10-01 by sampling a process wedged
        mid-reply (state stuck on "thinking"). The 2026-09-18 fix moved stop()
        into a worker thread with a timeout, and that thread did wedge, exactly
        as before:

            worker:    stream.stop() -> AudioOutputUnitStop -> HALB_Mutex::Lock
            IO thread: PortAudio startStopCallback -> AudioUnitGetProperty
                         -> recursive_mutex::lock          (each waits on the other)

        The timeout fired and the line "stayed up" — then the NEXT sentence
        constructed a new OutputStream on the event loop thread, and that
        blocked in Pa_OpenStream -> HALB_Mutex::Lock forever. Whole app frozen.

        Two changes kill it:
          1. Keep ONE stream open across sentences. The deadlock lives in
             PortAudio's start/stop path, and opening and stopping a stream per
             sentence ran that path dozens of times a conversation. Now it runs
             once at startup and again only when the device or rate changes.
          2. Every PortAudio call that can block goes through _audio_call: off
             the event loop, with a timeout.
        """
        if self._audio_wedged:
            return False
        key = (current_output_device(), sample_rate)
        if self._stream is not None and self._stream_key == key:
            return True
        await self._close_stream()
        if self._audio_wedged:
            return False

        block_size = int(sample_rate * 0.05)  # 50ms blocks
        holder = {}

        def _open():
            stream = sd.OutputStream(
                samplerate=sample_rate,
                channels=1,
                dtype="int16",
                blocksize=block_size,
                device=key[0],
            )
            stream.start()
            holder["stream"] = stream

        if not await self._audio_call(_open, "stream open"):
            return False
        self._stream = holder["stream"]
        self._stream_key = key
        return True

    async def _play_pcm(self, pcm_data: bytes, sample_rate: int):
        """Play PCM through speakers, feeding waveform to signal bus."""
        if not pcm_data or self._cancelled:
            return
        if not await self._ensure_stream(sample_rate):
            return

        samples = np.frombuffer(pcm_data, dtype=np.int16)
        block_size = int(sample_rate * 0.05)  # 50ms blocks
        stream = self._stream

        offset = 0
        while offset < len(samples) and not self._cancelled:
            end = min(offset + block_size, len(samples))
            block = samples[offset:end]
            # write() blocks until there is room in the buffer, which is the
            # pacing. It runs in a worker so a wedge cannot freeze the loop.
            if not await self._audio_call(
                lambda b=block: stream.write(b.reshape(-1, 1)), "stream write"
            ):
                return

            # Feed signal bus with this block
            signals.write_waveform(block.tobytes())

            offset = end

        if self._cancelled:
            self._cancelled = False

    def _set_speaking(self, speaking: bool):
        self._speaking = speaking
        if self._on_speaking_change:
            self._on_speaking_change(speaking)

    async def close(self):
        await self._close_stream()
        await self._http.aclose()
