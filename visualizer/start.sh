#!/bin/bash
# Lefty's Screen — macOS and Linux.
#
# Starts server.py if port 8777 is cold, then opens the page full screen.
# Quitting the browser leaves the server running and warm, so the next launch
# is instant.
#
# The screen works with or without the voice piece. With voice installed it
# shows Lefty listening, thinking and speaking. Without it, it sits at idle,
# which is correct rather than broken.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8777
URL="http://127.0.0.1:${PORT}/"
LOG="${TMPDIR:-/tmp}/lefty-visualizer.log"
PROFILE="${TMPDIR:-/tmp}/lefty-visualizer-chrome-profile"

cd "$DIR" || exit 1

# --- python ---------------------------------------------------------------
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [ -z "$PY" ]; then
  echo ""
  echo "  Lefty's screen needs Python 3, and this machine does not have it."
  echo "  Everything else still works. Install Python 3 and run this again."
  echo ""
  read -r -p "press return to close..."
  exit 1
fi

# --- server ---------------------------------------------------------------
if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/state"; then
  echo "screen server already up on ${PORT}"
else
  echo "starting the screen -> ${LOG}"
  nohup "$PY" "${DIR}/server.py" >>"$LOG" 2>&1 &
  for _ in $(seq 1 40); do
    curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/state" && break
    sleep 0.25
  done
fi

if ! curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/state"; then
  echo "The screen server did not start. Last few lines of the log:"
  tail -n 20 "$LOG"
  echo ""
  read -r -p "press return to close..."
  exit 1
fi

# --- browser --------------------------------------------------------------
# Kiosk mode in a throwaway profile, so it opens clean with no tabs, no
# bookmarks bar and nothing of yours in it.
CHROME=""
for c in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/usr/bin/google-chrome" \
  "/usr/bin/chromium" \
  "/usr/bin/chromium-browser"; do
  if [ -x "$c" ]; then CHROME="$c"; break; fi
done

if [ -n "$CHROME" ]; then
  rm -rf "$PROFILE"
  "$CHROME" \
    --user-data-dir="$PROFILE" \
    --no-first-run \
    --no-default-browser-check \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --autoplay-policy=no-user-gesture-required \
    --kiosk "$URL" >/dev/null 2>&1
else
  echo "Chrome not found, opening your default browser instead."
  echo "Press Control-Command-F (Mac) or F11 (Linux) for full screen."
  if command -v open >/dev/null 2>&1; then open "$URL"; else xdg-open "$URL"; fi
  sleep 3
fi
