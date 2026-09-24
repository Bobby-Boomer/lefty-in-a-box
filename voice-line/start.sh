#!/usr/bin/env bash
# Lefty's Voice launcher — starts the speech servers, then the voice line.\n# Paths are discovered, not hardcoded: run ./install.sh once and this finds it.
# Usage: ./run-voice-line.sh [--open-mic] [--cwd /path/to/project]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Find whisper wherever install.sh (or the user) put it. First hit wins.
WHISPER_BIN=""
for _c in \
    "$(command -v whisper-server 2>/dev/null)" \
    "$HOME/whisper.cpp/build/bin/whisper-server" \
    "/opt/homebrew/bin/whisper-server" \
    "/usr/local/bin/whisper-server"; do
    if [ -n "$_c" ] && [ -x "$_c" ]; then WHISPER_BIN="$_c"; break; fi
done

WHISPER_MODEL=""
for _m in \
    "$HOME/lefty/whisper-models/ggml-base.en.bin" \
    "$HOME/whisper.cpp/models/ggml-base.en.bin"; do
    if [ -f "$_m" ]; then WHISPER_MODEL="$_m"; break; fi
done
WHISPER_PORT=2022
KOKORO_PORT=8880

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[voice-line]${NC} $1"; }
warn() { echo -e "${YELLOW}[voice-line]${NC} $1"; }
err()  { echo -e "${RED}[voice-line]${NC} $1"; }

APP_PID=""
CLEANED=""
LOCK="$SCRIPT_DIR/.voice_line.lock"
LOCK_HELD=""

# ── Single instance guard ───────────────────────────────────────────────────
# Two voice lines at once is the bug behind most of the "Lefty froze" reports.
# They fight over the microphone and the push-to-talk key, and the older one
# keeps the whisper port, so the newer one silently has no speech server of its
# own. It looks exactly like a hang. Hit on 2026-09-18 and again on 2026-09-19.
#
# The lock stores the PID of the running app. A stale lock (process gone, or the
# PID reused by something that is not our main.py) is ignored and overwritten,
# so a crash can never leave the launcher unable to start.
if [ -f "$LOCK" ]; then
    OTHER="$(cat "$LOCK" 2>/dev/null || true)"
    if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null \
       && ps -p "$OTHER" -o command= 2>/dev/null | grep -q 'main\.py'; then
        if [ "${1:-}" = "--force" ]; then
            warn "Voice line already running (pid $OTHER). --force given, stopping it first."
            kill -TERM "$OTHER" 2>/dev/null || true
            for _ in $(seq 1 20); do kill -0 "$OTHER" 2>/dev/null || break; sleep 0.25; done
            kill -KILL "$OTHER" 2>/dev/null || true
            shift
        else
            err "A voice line is ALREADY RUNNING (pid $OTHER)."
            err "Two at once fight over the mic and the push-to-talk key, which is what"
            err "makes it look frozen. Use that window, or close it and start again."
            err "To take over anyway: ./run-voice-line.sh --force"
            exit 1
        fi
    else
        warn "Ignoring stale lock file (pid ${OTHER:-empty} is not a running voice line)."
    fi
fi

cleanup() {
    # EXIT fires after INT/TERM too — only do the work once.
    if [ -n "$CLEANED" ]; then
        return 0
    fi
    CLEANED=1

    log "Shutting down..."

    # Stop the app first so it can't rewrite the state files we're about to remove.
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill -TERM "$APP_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$APP_PID" 2>/dev/null || break
            sleep 0.25
        done
        kill -KILL "$APP_PID" 2>/dev/null || true
    fi

    if [ -n "${WHISPER_PID:-}" ] && kill "$WHISPER_PID" 2>/dev/null; then
        log "Stopped whisper server"
    fi
    if [ -n "${KOKORO_PID:-}" ] && kill "$KOKORO_PID" 2>/dev/null; then
        log "Stopped kokoro server"
    fi

    rm -f "$SCRIPT_DIR/.voice_state" "$SCRIPT_DIR/.voice_waveform" "$SCRIPT_DIR/.voice_loading_pid"

    # Release the single-instance lock, but only if this run took it. Otherwise
    # a refused second launch would delete the lock held by the live one.
    if [ -n "$LOCK_HELD" ]; then
        rm -f "$LOCK"
    fi
    return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ── Load secrets ────────────────────────────────────────────────────────────
# .env is gitignored. Existing env vars win, so you can override per-run.
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/.env"
    set +a
fi

# ── Preflight checks ───────────────────────────────────────────────────────

# Check ffmpeg
if ! command -v ffmpeg &>/dev/null; then
    err "ffmpeg is not installed. On a Mac:  brew install ffmpeg"
    exit 1
fi

# Check uv
if ! command -v uv &>/dev/null; then
    err "uv is not installed. Run ./install.sh and it will offer to do it."
    exit 1
fi

# Check ELEVENLABS_API_KEY
if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
    log "No ElevenLabs key set, so Lefty speaks through Kokoro. That is the normal setup and it costs nothing."
fi

# ── Start whisper.cpp server ────────────────────────────────────────────────

WHISPER_PID=""
if curl -sf "http://localhost:$WHISPER_PORT/v1/audio/transcriptions" >/dev/null 2>&1 || \
   curl -sf "http://localhost:$WHISPER_PORT/health" >/dev/null 2>&1; then
    log "Whisper server already running on port $WHISPER_PORT"
else
    if [ -z "$WHISPER_BIN" ]; then
        err "whisper-server is not installed, so Lefty cannot hear you."
        err "Run the installer in this folder and it will sort it:  ./install.sh"
        exit 1
    fi
    if [ -z "$WHISPER_MODEL" ]; then
        err "The speech model is missing, so Lefty cannot hear you."
        err "Run the installer in this folder and it will fetch it:  ./install.sh"
        exit 1
    fi
    log "Starting whisper server on port $WHISPER_PORT..."
    "$WHISPER_BIN" \
        --model "$WHISPER_MODEL" \
        --port "$WHISPER_PORT" \
        --language en \
        --no-timestamps \
        >/dev/null 2>&1 &
    WHISPER_PID=$!

    # Wait for server to come up
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:$WHISPER_PORT/health" >/dev/null 2>&1; then
            log "Whisper server ready (PID $WHISPER_PID)"
            break
        fi
        if [ "$i" -eq 30 ]; then
            err "Whisper server failed to start after 30s"
            exit 1
        fi
        sleep 1
    done
fi

# ── Start Kokoro TTS server (optional fallback) ────────────────────────────

KOKORO_PID=""
if curl -sf "http://localhost:$KOKORO_PORT/health" >/dev/null 2>&1; then
    log "Kokoro server already running on port $KOKORO_PORT"
else
    KOKORO_SERVER="$SCRIPT_DIR/services/kokoro/src/kokoro_server/server.py"
    if [ -f "$KOKORO_SERVER" ]; then
        log "Starting Kokoro TTS server on port $KOKORO_PORT..."
        cd "$SCRIPT_DIR/services/kokoro"
        uv run python "$KOKORO_SERVER" >/dev/null 2>&1 &
        KOKORO_PID=$!
        cd "$SCRIPT_DIR"

        # Wait briefly — don't block if Kokoro takes time to load models
        for i in $(seq 1 10); do
            if curl -sf "http://localhost:$KOKORO_PORT/health" >/dev/null 2>&1; then
                log "Kokoro server ready (PID $KOKORO_PID)"
                break
            fi
            if [ "$i" -eq 10 ]; then
                warn "Kokoro still loading (will be available as fallback when ready)"
            fi
            sleep 1
        done
    else
        warn "Kokoro server not installed. ElevenLabs only (no fallback)."
    fi
fi

# ── macOS permissions reminder ──────────────────────────────────────────────

if [ "$(uname)" = "Darwin" ]; then
    echo ""
    warn "macOS permissions needed:"
    warn "  - Input Monitoring: System Settings > Privacy > Input Monitoring > Terminal"
    warn "  - Microphone: System Settings > Privacy > Microphone > Terminal"
    warn "  (Grant these if prompted, then re-run)"
    echo ""
fi

# ── Launch voice line ───────────────────────────────────────────────────────

log "Starting Voice Line..."
cd "$SCRIPT_DIR"

# Not exec'd: this shell has to stay alive to hold the trap, otherwise a TERM
# goes straight to the app and the state files are left behind.
uv run python main.py "$@" &
APP_PID=$!

# Claim the single-instance lock now that the app actually exists.
echo "$APP_PID" > "$LOCK"
LOCK_HELD=1

# A signal interrupts wait; the trap runs, then this returns non-zero. The ||
# keeps set -e from killing the script before we can read the status.
APP_STATUS=0
wait "$APP_PID" || APP_STATUS=$?

cleanup
exit "$APP_STATUS"
