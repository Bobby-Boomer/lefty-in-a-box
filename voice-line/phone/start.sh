#!/usr/bin/env bash
# Phone line: talk to your agent from your phone, on your home Wi-Fi. Mac only for now.
# Needs the voice line's speech servers: whisper-server :2022 and Kokoro :8880.
# Start the desk voice line once first, or use always-on.sh, which starts them itself.
#
# HTTPS is required because phone browsers only allow the microphone on secure pages.
# A self-signed certificate is made on first run, so the phone shows a warning once.
#
# fastapi and uvicorn come in with --with, NOT from the project's own dependencies.
# On the author's machine they were only present because the Kokoro service had
# installed them into the shared venv; a fresh install without Kokoro would have
# failed with "No module named uvicorn". --with makes the phone line carry its own.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VL="$(dirname "$HERE")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
PORT="${PHONE_PORT:-8790}"
# Same keys as the voice line (ElevenLabs etc). Existing env vars win.
if [ -f "$VL/.env" ]; then set -a; . "$VL/.env"; set +a; fi
CERT="$HERE/.cert.pem"; KEY="$HERE/.key.pem"
if [ ! -f "$CERT" ]; then
  SAN="DNS:$(scutil --get LocalHostName 2>/dev/null || hostname -s).local,DNS:localhost,IP:127.0.0.1"
  for i in en0 en1; do ip=$(ipconfig getifaddr $i 2>/dev/null || true); [ -n "$ip" ] && SAN="$SAN,IP:$ip"; done
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=Lefty phone line" \
    -addext "subjectAltName=$SAN" -keyout "$KEY" -out "$CERT" >/dev/null 2>&1
  chmod 600 "$KEY"
fi
cd "$HERE"
echo "Phone line starting on port $PORT. Get your link with: bash $HERE/url.sh"
exec uv run --project "$VL" --with fastapi --with uvicorn python -m uvicorn server:app \
  --host 0.0.0.0 --port "$PORT" --ssl-keyfile "$KEY" --ssl-certfile "$CERT" --log-level warning
