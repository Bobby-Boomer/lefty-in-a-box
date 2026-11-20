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

# THE SYMPTOM THIS FIXES (found 2026-11-20): one morning the always-on phone line answers
# every question with its generic failure line and nothing in the log explains it. The
# cause is not the phone line at all — the interactive `claude auth login` session it was
# borrowing has a HARD expiry that renewing does not move. `claude auth status` shows the
# date in "loginExpiresAt". After it passes, the CLI returns:
#
#   "Failed to authenticate: this login reached its time limit and cannot be renewed.
#    Run `claude auth login` to sign in again, or use `claude setup-token` and set
#    CLAUDE_CODE_OAUTH_TOKEN for unattended jobs"
#
# An always-on job has nobody at the keyboard to re-run a browser login, so it needs its
# own long-lived token. Run `claude setup-token` once (needs a Claude subscription) and
# drop the token in the file below, chmod 600.
#
# Deliberately NOT exported in a shell profile: a token session runs at reduced scope
# ("env-var and setup-token sessions default to user:inference only"), so putting it in
# ~/.zshenv would quietly downgrade your own interactive sessions too. Set it here, for
# this job only, and leave your desk sessions on the full-scope login.
#
# No-op when the file is absent, so nothing changes until you create it.
PHONE_TOKEN_FILE="${PHONE_TOKEN_FILE:-$HOME/.claude-oauth-token}"
if [ -r "$PHONE_TOKEN_FILE" ]; then
  _tok="$(tr -d ' \t\r\n' < "$PHONE_TOKEN_FILE" 2>/dev/null)"
  if [ -n "$_tok" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$_tok"
    log "using the long-lived token from $PHONE_TOKEN_FILE"
  fi
  unset _tok
fi

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
