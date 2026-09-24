"""Mic capture and transcription via local whisper.cpp server."""

import asyncio
import io
import os
import re
import struct
import time
import wave
import numpy as np
import sounddevice as sd
import httpx
import webrtcvad

WHISPER_URL = "http://localhost:2022/inference"
SAMPLE_RATE = 16000
CHANNELS = 1
DTYPE = "int16"

# Open-mic VAD settings
VAD_FRAME_MS = 30
VAD_FRAME_SAMPLES = int(SAMPLE_RATE * VAD_FRAME_MS / 1000)
MIN_SPEECH_MS = 240
SILENCE_TIMEOUT_MS = 800

# Discard clips shorter than a deliberate hold (int16 mono @ 16kHz)
MIN_AUDIO_BYTES = int(SAMPLE_RATE * 2 * 0.25)

# Bracketed non-speech markers whisper emits
_BRACKET_RE = re.compile(r"\[.*?\]")

# A mic quieter than this across a whole check is almost certainly muted or dead
SILENT_RMS = 15


def resolve_device(spec: str | int | None) -> int | None:
    """Resolve a device index or name substring to a sounddevice index.

    None (or empty) means the system default. Continuity Camera mics can't be
    set as the macOS default input, so targeting them requires this.
    """
    if spec is None or spec == "":
        return None
    if isinstance(spec, int) or str(spec).isdigit():
        return int(spec)
    needle = str(spec).lower()
    matches = [
        (i, d["name"])
        for i, d in enumerate(sd.query_devices())
        if d["max_input_channels"] > 0 and needle in d["name"].lower()
    ]
    if not matches:
        raise ValueError(f"No input device matching {spec!r}. Run --list-devices.")
    if len(matches) > 1:
        names = ", ".join(f"[{i}] {n}" for i, n in matches)
        raise ValueError(f"{spec!r} is ambiguous: {names}")
    return matches[0][0]


def list_devices() -> str:
    """Human-readable list of input devices, marking the system default."""
    default = sd.default.device[0]
    lines = ["Input devices:"]
    for i, d in enumerate(sd.query_devices()):
        if d["max_input_channels"] > 0:
            mark = "  <-- system default" if i == default else ""
            lines.append(f"  [{i}] {d['name']}  ({int(d['default_samplerate'])}Hz){mark}")
    return "\n".join(lines)


class Ears:
    def __init__(self, device: str | int | None = None):
        self._recording = False
        self._frames: list[bytes] = []
        self._stream = None
        self._http = httpx.AsyncClient(timeout=30.0)
        # CLI arg wins, then env, then system default
        # Keep the spec, not just the resolved index: indexes shift when the
        # audio device list changes, so a retry has to re-resolve by name.
        self._device_spec = device if device is not None else os.environ.get("VOICE_INPUT_DEVICE")
        self._device = resolve_device(self._device_spec)

    @property
    def device_name(self) -> str:
        idx = self._device if self._device is not None else sd.default.device[0]
        return sd.query_devices(idx)["name"]

    def check_level(self, seconds: float = 1.0) -> tuple[int, bool]:
        """Sample the mic briefly. Returns (rms, looks_alive).

        A muted or disconnected mic otherwise fails silently — you only find
        out when whisper returns nothing for every turn.
        """
        try:
            rec = sd.rec(
                int(SAMPLE_RATE * seconds),
                samplerate=SAMPLE_RATE,
                channels=CHANNELS,
                dtype=DTYPE,
                device=self._device,
            )
            sd.wait()
            rms = int(np.sqrt((rec.flatten().astype(float) ** 2).mean()))
            return rms, rms >= SILENT_RMS
        except Exception as e:
            print(f"[ears] Mic check failed: {e}")
            return 0, False

    def force_close(self):
        """Tear the mic down. Safe to call any time, from any state.

        CRITICAL: the old code only closed the stream when it was `.active`, and
        only from the normal path. If anything raised between start and stop --
        a cancelled turn, a failed transcribe, Ctrl-C -- the stream was left
        open holding CoreAudio. Opening another on top of that is what wedged
        the audio system and forced a restart.
        """
        st, self._stream = self._stream, None
        self._recording = False
        if st is None:
            return
        try:
            st.stop()
        except Exception:
            pass
        try:
            st.close()
        except Exception:
            pass

    def start_listening(self):
        """Open mic and start capturing audio.

        Retries, because opening an input stream is not reliably atomic on macOS.
        `PaErrorCode -9986` ("Internal PortAudio error") comes back whenever
        CoreAudio's device list is mid-change or another app is grabbing the mic
        at that instant -- adding a virtual device, a browser joining a call, a
        multi-output device appearing. It killed the whole voice line on
        2026-09-21 because the exception propagated straight out of main().

        The error is transient. PortAudio just needs re-initialising so it
        re-reads the device list, and a moment to settle.
        """
        # Always start from a clean slate. A stream left over from a previous
        # turn is the thing that wedges CoreAudio.
        self.force_close()
        self._frames = []
        self._recording = True

        last = None
        for attempt in range(5):
            try:
                self._stream = sd.InputStream(
                    samplerate=SAMPLE_RATE,
                    channels=CHANNELS,
                    dtype=DTYPE,
                    blocksize=int(SAMPLE_RATE * 0.05),  # 50ms blocks
                    callback=self._audio_callback,
                    device=self._device,
                )
                self._stream.start()
                if attempt:
                    print(f"[ears] mic opened on attempt {attempt + 1}", flush=True)
                return
            except Exception as e:
                last = e
                self._stream = None
                print(f"[ears] mic open failed ({e}); retrying", flush=True)
                time.sleep(0.25 * (attempt + 1))
                try:
                    # Force PortAudio to re-read the device list. This is the
                    # actual cure for -9986 after the devices changed underneath.
                    sd._terminate()
                    sd._initialize()
                except Exception:
                    pass
                # The index may have shifted when the device list changed.
                try:
                    self._device = resolve_device(self._device_spec)
                except Exception:
                    pass

        self._recording = False
        raise RuntimeError(
            f"Could not open the microphone after 5 attempts: {last}. "
            "Something else is holding it, or the audio devices are mid-change."
        )

    def stop_listening(self) -> bytes:
        """Close mic and return captured audio as WAV bytes."""
        try:
            return self._frames_to_wav()
        finally:
            # finally, so the mic is released even if framing raises
            self.force_close()

    def _audio_callback(self, indata, frames, time_info, status):
        if self._recording:
            self._frames.append(indata.copy().tobytes())

    def _frames_to_wav(self) -> bytes:
        if not self._frames:
            return b""
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)  # int16
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(b"".join(self._frames))
        return buf.getvalue()

    async def transcribe(self, wav_bytes: bytes) -> str:
        """Send WAV to whisper.cpp server, return text."""
        if not wav_bytes or len(wav_bytes) < MIN_AUDIO_BYTES:
            return ""
        try:
            resp = await self._http.post(
                WHISPER_URL,
                files={"file": ("audio.wav", wav_bytes, "audio/wav")},
                data={"model": "whisper-1", "language": "en"},
            )
            resp.raise_for_status()
            result = resp.json()
            # Strip whisper's non-speech markers ([Music], [BLANK_AUDIO], ...).
            # Without this a noisy PTT release becomes a junk turn to Claude.
            return _BRACKET_RE.sub("", result.get("text", "")).strip()
        except Exception as e:
            print(f"[ears] Transcription error: {e}")
            return ""

    async def listen_open_mic(self) -> str:
        """Open-mic mode: VAD-based endpointing, returns transcribed text."""
        vad = webrtcvad.Vad(2)  # aggressiveness 2
        frames = []
        speech_frames = 0
        silence_frames = 0
        max_silence = int(SILENCE_TIMEOUT_MS / VAD_FRAME_MS)
        min_speech = int(MIN_SPEECH_MS / VAD_FRAME_MS)
        heard_speech = False

        stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype=DTYPE,
            blocksize=VAD_FRAME_SAMPLES,
            device=self._device,
        )
        stream.start()

        try:
            while True:
                data, _ = stream.read(VAD_FRAME_SAMPLES)
                frame_bytes = data.tobytes()
                is_speech = vad.is_speech(frame_bytes, SAMPLE_RATE)

                if is_speech:
                    speech_frames += 1
                    silence_frames = 0
                    if speech_frames >= min_speech // 2:
                        heard_speech = True
                else:
                    silence_frames += 1

                frames.append(frame_bytes)

                if heard_speech and silence_frames >= max_silence:
                    break

                await asyncio.sleep(0)  # yield to event loop
        finally:
            stream.stop()
            stream.close()

        if speech_frames < min_speech:
            return ""

        # Build WAV
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(b"".join(frames))

        # transcribe() already strips bracketed non-speech markers
        return await self.transcribe(buf.getvalue())

    async def close(self):
        await self._http.aclose()
