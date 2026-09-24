#!/usr/bin/env python3
"""
Stream visualizer bridge server.

Two jobs, nothing else:
  1. Serve index.html (and anything in assets/)
  2. Serve /state as JSON, read from the voice-line signal bus

STRICTLY READ-ONLY on the bus. This process never writes .voice_state,
.voice_waveform, or .voice_alert.

  ./server.py            -> real bus,   127.0.0.1:8777
  ./server.py --mock     -> scripted loop, 127.0.0.1:8778 (bus untouched)
"""

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# --- configuration ----------------------------------------------------------

HOST = "127.0.0.1"
PORT = 8777
MOCK_PORT = 8778

# Where the voice line writes its signal files. Override with LEFTY_BUS_DIR if
# the voice piece lives somewhere else. If the voice piece is not installed at
# all, these files simply never exist and the screen sits at "idle" -- which is
# correct, not an error.
BUS_DIR = os.environ.get("LEFTY_BUS_DIR") or os.path.expanduser("~/lefty/voice-line")
STATE_FILE = os.path.join(BUS_DIR, ".voice_state")
WAVEFORM_FILE = os.path.join(BUS_DIR, ".voice_waveform")
ALERT_FILE = os.path.join(BUS_DIR, ".voice_alert")

WEB_ROOT = os.path.dirname(os.path.abspath(__file__))

# A waveform older than this is not "live" any more.
WAVEFORM_FRESH_SEC = 2.0

# mean(abs(sample)) is small even for loud speech; scale it into 0..1.
LEVEL_GAIN = 6.0

VALID_STATES = ("idle", "listening", "thinking", "speaking")

# --- bus reading ------------------------------------------------------------


def read_state_file():
    """Plain text state, or 'idle' if unreadable/garbage."""
    try:
        with open(STATE_FILE, "r") as f:
            s = f.read().strip().lower()
        return s if s in VALID_STATES else "idle"
    except (OSError, ValueError):
        return "idle"


def read_waveform():
    """
    Return (level, samples, is_live).

    level is mean absolute sample scaled into 0..1.
    is_live is True only when ts is within WAVEFORM_FRESH_SEC of now.
    """
    try:
        with open(WAVEFORM_FILE, "r") as f:
            data = json.load(f)
        ts = float(data.get("ts", 0.0))
        samples = data.get("samples") or []
        if not isinstance(samples, list) or not samples:
            return 0.0, [], False
        samples = [float(x) for x in samples]
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return 0.0, [], False

    age = time.time() - ts
    is_live = 0.0 <= age <= WAVEFORM_FRESH_SEC

    mean_abs = sum(abs(x) for x in samples) / len(samples)
    level = max(0.0, min(1.0, mean_abs * LEVEL_GAIN))
    return level, samples, is_live


def read_alert():
    return os.path.exists(ALERT_FILE)


def bus_state():
    """
    Compose the /state payload from the bus.

    STOMP TOLERANCE: a fresh waveform means the voice line is speaking right
    now, whatever the state file happens to say. Some other process
    overwriting .voice_state mid-sentence must not cut the show off, so a
    live waveform always wins.
    """
    state = read_state_file()
    level, samples, live = read_waveform()

    if live:
        state = "speaking"
    else:
        level = 0.0
        samples = []

    return {
        "state": state,
        "level": round(level, 4),
        "alert": read_alert(),
        "samples": [round(s, 4) for s in samples],
    }


# --- mock: scripted loop, never touches the bus -----------------------------

# (state, duration_seconds)
MOCK_SCRIPT = [
    ("idle", 6.0),
    ("listening", 5.0),
    ("thinking", 5.0),
    ("speaking", 10.0),
    ("idle", 3.0),
    ("alert", 5.0),
    ("idle", 4.0),
]
MOCK_CYCLE = sum(d for _, d in MOCK_SCRIPT)

_MOCK_T0 = time.time()


def mock_state():
    import math

    t = (time.time() - _MOCK_T0) % MOCK_CYCLE
    acc = 0.0
    step, held = MOCK_SCRIPT[0][0], 0.0
    for name, dur in MOCK_SCRIPT:
        if t < acc + dur:
            step, held = name, t - acc
            break
        acc += dur

    alert = step == "alert"
    state = "idle" if alert else step

    level = 0.0
    samples = []
    if state == "speaking":
        # Synthetic breathing voice: syllable envelope over a slow breath,
        # with short gaps so the centerpiece visibly rests between words.
        breath = 0.55 + 0.45 * math.sin(held * 0.9)
        syll = abs(math.sin(held * 5.5)) ** 1.6
        gap = 1.0 if (held % 3.4) < 2.7 else 0.08
        level = max(0.0, min(1.0, breath * syll * gap))
        samples = [
            level * math.sin(i * 0.55 + held * 9.0) * (0.6 + 0.4 * math.sin(i * 0.17))
            for i in range(64)
        ]

    return {
        "state": state,
        "level": round(level, 4),
        "alert": alert,
        "samples": [round(s, 4) for s in samples],
    }


# --- http -------------------------------------------------------------------

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
    ".json": "application/json",
}


class Handler(BaseHTTPRequestHandler):
    server_version = "VoiceVisualizer/1.0"
    mock = False

    def log_message(self, fmt, *args):
        # One line per request would drown the log at 10Hz polling.
        pass

    def _send(self, code, body, ctype, cache=False):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if not cache:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        path = self.path.split("?", 1)[0]

        if path == "/state":
            payload = mock_state() if self.mock else bus_state()
            self._send(200, json.dumps(payload).encode(), "application/json")
            return

        if path in ("/", "/index.html"):
            path = "/index.html"

        # Serve only files under WEB_ROOT.
        rel = os.path.normpath(path.lstrip("/"))
        if rel.startswith("..") or os.path.isabs(rel):
            self._send(403, b"forbidden", "text/plain")
            return

        full = os.path.join(WEB_ROOT, rel)
        if not os.path.isfile(full):
            self._send(404, b"not found", "text/plain")
            return

        ext = os.path.splitext(full)[1].lower()
        try:
            with open(full, "rb") as f:
                body = f.read()
        except OSError:
            self._send(500, b"read error", "text/plain")
            return

        self._send(200, body, MIME.get(ext, "application/octet-stream"))


def main():
    mock = "--mock" in sys.argv
    port = MOCK_PORT if mock else PORT
    Handler.mock = mock

    httpd = ThreadingHTTPServer((HOST, port), Handler)
    httpd.daemon_threads = True
    mode = "MOCK (scripted loop, bus untouched)" if mock else "LIVE (reading %s)" % BUS_DIR
    print("visualizer serving http://%s:%d  --  %s" % (HOST, port, mode), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye", flush=True)
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
