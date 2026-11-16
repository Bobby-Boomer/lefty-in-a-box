#!/usr/bin/env bash
# Launcher for the always-on phone line (installed by autostart.sh as a launchd job).
#
# WHY it starts whisper and Kokoro itself: the desk voice line starts those servers AND
# stops them when you close it. Before this, closing the desk voice line made the phone
# line go deaf with no error. The desk launcher already reuses servers it finds running
# and only stops the ones it started, so the two never fight.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VL="$(dirname "$HERE")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin"
log() { echo "[phone-line $(date '+%F %T')] $*"; }

if ! curl -sf http://localhost:2022/health >/dev/null 2>&1; then
  WB=""; for c in "$(command -v whisper-server 2>/dev/null)" "$HOME/whisper.cpp/build/bin/whisper-server" \
      /opt/homebrew/bin/whisper-server /usr/local/bin/whisper-server; do
    [ -n "$c" ] && [ -x "$c" ] && { WB="$c"; break; }; done
  WM=""; for m in "$HOME/lefty/whisper-models/ggml-base.en.bin" "$HOME/whisper.cpp/models/ggml-base.en.bin"; do
    [ -f "$m" ] && { WM="$m"; break; }; done
  if [ -n "$WB" ] && [ -n "$WM" ]; then
    log "whisper down, starting it"
    nohup "$WB" --model "$WM" --port 2022 --language en --no-timestamps >/dev/null 2>&1 &
    for _ in $(seq 1 30); do curl -sf http://localhost:2022/health >/dev/null 2>&1 && break; sleep 1; done
  else
    log "whisper-server or its model not found; the phone will not be able to hear you"
  fi
fi
if ! curl -sf http://localhost:8880/health >/dev/null 2>&1 && [ -d "$VL/services/kokoro" ]; then
  log "kokoro down, starting it"
  (cd "$VL/services/kokoro" && nohup uv run python src/kokoro_server/server.py >/dev/null 2>&1 &)
fi
log "starting phone line"
exec "$HERE/start.sh"
