"""Visualizer signal bus — writes state and waveform files for external consumers."""

import json
import time
import os
import numpy as np

_PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
_STATE_FILE = os.path.join(_PROJECT_ROOT, ".voice_state")
_WAVEFORM_FILE = os.path.join(_PROJECT_ROOT, ".voice_waveform")
_LOADING_PID_FILE = os.path.join(_PROJECT_ROOT, ".voice_loading_pid")

# Throttle waveform writes to ~15fps
_MIN_WAVEFORM_INTERVAL = 1.0 / 15.0
_last_waveform_ts = 0.0


def _safe_write(path: str, content: str) -> None:
    try:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            f.write(content)
        os.replace(tmp, path)
    except Exception:
        pass


# A turn can keep running long after the speaking stops -- tool calls, reading
# files, driving the browser. The mouth drains its queue and reports "idle",
# which made the visualizer say READY while the app was still busy and could not
# accept a new press. Bobby hit this repeatedly: "it says idle but the control
# key will not turn on the mic."
#
# So "idle" is now a claim that has to be earned. While a turn is in flight the
# app sets busy, and any attempt to fall back to idle is held at "thinking"
# until the turn actually ends.
_busy = False


def set_busy(busy: bool) -> None:
    """True while a turn is running. Blocks premature 'idle'."""
    global _busy
    _busy = bool(busy)
    if not busy:
        _safe_write(_STATE_FILE, "idle")


def set_state(state: str) -> None:
    """Write state: idle, listening, thinking, speaking, working."""
    if state == "idle" and _busy:
        # Not idle. Still working. Say so rather than lie.
        _safe_write(_STATE_FILE, "thinking")
        return
    _safe_write(_STATE_FILE, state)


def write_waveform(pcm_block: bytes, sample_width: int = 2) -> None:
    """Downsample PCM block to 64 points and write JSON.

    CRITICAL self-heal: every waveform write also re-writes state to speaking.
    """
    global _last_waveform_ts
    now = time.time()
    if now - _last_waveform_ts < _MIN_WAVEFORM_INTERVAL:
        return
    _last_waveform_ts = now

    try:
        samples = np.frombuffer(pcm_block, dtype=np.int16)
        if len(samples) == 0:
            return
        # Downsample to 64 points
        if len(samples) >= 64:
            indices = np.linspace(0, len(samples) - 1, 64, dtype=int)
            downsampled = np.abs(samples[indices]).astype(float).tolist()
        else:
            downsampled = np.abs(samples).astype(float).tolist()
            downsampled.extend([0.0] * (64 - len(downsampled)))

        payload = json.dumps({"ts": now, "samples": downsampled})
        _safe_write(_WAVEFORM_FILE, payload)
    except Exception:
        pass

    # Self-heal: re-assert speaking state
    set_state("speaking")


def set_loading_pid(pid: int) -> None:
    _safe_write(_LOADING_PID_FILE, str(pid))


def clear_loading_pid() -> None:
    try:
        os.remove(_LOADING_PID_FILE)
    except Exception:
        pass


def cleanup() -> None:
    """Remove signal files on shutdown."""
    for f in (_STATE_FILE, _WAVEFORM_FILE, _LOADING_PID_FILE):
        try:
            os.remove(f)
        except Exception:
            pass
