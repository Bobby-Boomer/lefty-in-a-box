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

# THE SYMPTOM THIS FIXES (found 2026-11-15): on cell service, Safari rejected the page with a
# certificate warning, which reads exactly like "the tunnel is broken." The tunnel was fine — the
# server answered 401 over Tailscale all along. The cert simply did not list the Tailscale address in
# its SAN, because the first version only added localhost and the LAN IPs. So include the Tailscale
# name and IPs too, and the one cert covers home and away.
#
# Tailscale's CLI lives inside the app bundle on macOS and is NOT on PATH, so `which tailscale`
# finding nothing does not mean Tailscale is missing. TAILSCALE_BIN overrides for other installs.
TS_BIN="${TAILSCALE_BIN:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
command -v tailscale >/dev/null 2>&1 && TS_BIN="${TAILSCALE_BIN:-$(command -v tailscale)}"
ts_name() {
  [ -x "$TS_BIN" ] || return 1
  "$TS_BIN" status --json 2>/dev/null | /usr/bin/python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: raise SystemExit
print(((d.get("Self") or {}).get("DNSName") or "").rstrip("."))' 2>/dev/null
}
ts_ips() { [ -x "$TS_BIN" ] && "$TS_BIN" ip -4 2>/dev/null; }

if [ ! -f "$CERT" ]; then
  SAN="DNS:$(scutil --get LocalHostName 2>/dev/null || hostname -s).local,DNS:localhost,IP:127.0.0.1"
  for i in en0 en1; do ip=$(ipconfig getifaddr $i 2>/dev/null || true); [ -n "$ip" ] && SAN="$SAN,IP:$ip"; done
  tsn="$(ts_name || true)"; [ -n "${tsn:-}" ] && SAN="$SAN,DNS:$tsn"
  for tip in $(ts_ips || true); do SAN="$SAN,IP:$tip"; done
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=Lefty phone line" \
    -addext "subjectAltName=$SAN" -keyout "$KEY" -out "$CERT" >/dev/null 2>&1
  chmod 600 "$KEY"
fi

# If Tailscale was set up AFTER the cert was first made, the cert will not cover it. Rebuild once
# rather than leaving the user with a warning they cannot explain.
if [ -f "$CERT" ]; then
  tsn="$(ts_name || true)"
  if [ -n "${tsn:-}" ] && ! openssl x509 -in "$CERT" -noout -text 2>/dev/null | grep -q "$tsn"; then
    echo "Tailscale name not in the certificate yet; rebuilding it so away-from-home works."
    mv -f "$CERT" "$CERT.pre-tailscale"; mv -f "$KEY" "$KEY.pre-tailscale"
    SAN="DNS:$(scutil --get LocalHostName 2>/dev/null || hostname -s).local,DNS:localhost,IP:127.0.0.1"
    for i in en0 en1; do ip=$(ipconfig getifaddr $i 2>/dev/null || true); [ -n "$ip" ] && SAN="$SAN,IP:$ip"; done
    SAN="$SAN,DNS:$tsn"
    for tip in $(ts_ips || true); do SAN="$SAN,IP:$tip"; done
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=Lefty phone line" \
      -addext "subjectAltName=$SAN" -keyout "$KEY" -out "$CERT" >/dev/null 2>&1
    chmod 600 "$KEY"
  fi
fi
cd "$HERE"
echo "Phone line starting on port $PORT. Get your link with: bash $HERE/url.sh"
exec uv run --project "$VL" --with fastapi --with uvicorn python -m uvicorn server:app \
  --host 0.0.0.0 --port "$PORT" --ssl-keyfile "$KEY" --ssl-certfile "$CERT" --log-level warning
