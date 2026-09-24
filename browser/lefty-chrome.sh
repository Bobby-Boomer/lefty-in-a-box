#!/bin/bash
# The shared browser — macOS and Linux.
#
# Starts a SECOND Chrome that your AI can see and drive. Your everyday Chrome
# is never touched.
#
# Why a second one: Chrome 136 and later refuse --remote-debugging-port on the
# default profile. That is a deliberate security change, not a bug, and there is
# no flag that turns it off. So this runs an entirely separate profile.
#
# The debugging port is bound to 127.0.0.1 only. Nothing outside this machine
# can reach it. Anything ON this machine can drive this window, which is exactly
# why it is a separate profile with only the logins you choose to put in it.

set -euo pipefail

PORT="${LEFTY_CHROME_PORT:-9222}"
PROFILE="${LEFTY_CHROME_PROFILE:-$HOME/lefty/chrome-profile}"

CHROME=""
for c in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/usr/bin/google-chrome" \
  "/usr/bin/chromium" \
  "/usr/bin/chromium-browser"; do
  if [ -x "$c" ]; then CHROME="$c"; break; fi
done

if [ -z "$CHROME" ]; then
  echo "Google Chrome not found. Install Chrome, then run this again." >&2
  exit 1
fi

# Already listening? Then it is up. Do not start a second one — two browsers
# fighting over one profile is a mess to unpick.
if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/json/version"; then
  echo "Already running on port ${PORT}. Nothing to do."
  echo "Profile: ${PROFILE}"
  exit 0
fi

mkdir -p "$PROFILE"

# --use-fake-ui-for-media-stream auto-accepts Chrome's camera/mic bubble. That
# bubble is a NATIVE dialog, so an AI driving the browser cannot click it and
# getUserMedia just hangs forever. It does NOT fake your devices — your real
# camera and mic are still used, it only skips the prompt.
"$CHROME" \
  --remote-debugging-port="${PORT}" \
  --remote-allow-origins="http://127.0.0.1:${PORT}" \
  --user-data-dir="$PROFILE" \
  --use-fake-ui-for-media-stream \
  --no-first-run \
  --no-default-browser-check \
  >/dev/null 2>&1 &

for _ in $(seq 1 30); do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/json/version"; then
    echo "Chrome is up. Your AI can attach to it now."
    echo "Port:    ${PORT}"
    echo "Profile: ${PROFILE}"
    echo ""
    echo "Log into whatever sites you want it to work in, once, in THIS window."
    echo "The profile persists, so those logins survive a restart."
    exit 0
  fi
  sleep 0.5
done

echo "Chrome started but port ${PORT} never answered." >&2
echo "Usually that means another Chrome is already using this profile folder." >&2
exit 1
