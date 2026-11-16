#!/usr/bin/env bash
# Prints the phone link (with the access key). Show it as a QR on the Mac screen; never paste it into a note.
HERE="$(cd "$(dirname "$0")" && pwd)"; PORT="${PHONE_PORT:-8790}"
for i in en0 en1; do ip=$(ipconfig getifaddr $i 2>/dev/null) && break; done
# The key is created the first time the server starts, so wait briefly for it.
for _ in $(seq 1 30); do [ -f "$HERE/.token" ] && break; sleep 1; done
[ -f "$HERE/.token" ] || { echo "No access key yet: start the phone line first (bash $HERE/start.sh)."; exit 1; }
echo "https://$ip:$PORT/?k=$(cat "$HERE/.token")"
