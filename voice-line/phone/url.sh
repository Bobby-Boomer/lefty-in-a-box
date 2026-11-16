#!/usr/bin/env bash
# Prints the phone link (with the access key). Show it as a QR on the Mac screen; never paste it into a note.
#
# THE SYMPTOM THIS FIXES (found 2026-11-15): the phone line worked beautifully at home and then did
# nothing at all on cell service. It was not the tunnel and it was not the browser. This script was
# handing out the Mac's LAN address (a 192.168.x.x from `ipconfig getifaddr en0`), and a private LAN
# address resolves to nothing once the phone leaves the Wi-Fi.
#
# So: if Tailscale is installed and online, print the Tailscale MagicDNS name instead. That link works
# on cell AND on home Wi-Fi, so there is no second link to remember. Pass --lan to force the local
# address (useful if you deliberately do not want the traffic on the tailnet).
#
# You also need the cert to cover the Tailscale name — see start.sh. Without that, this prints a
# perfectly good URL and Safari refuses it, which looks like a network failure and is not one.
HERE="$(cd "$(dirname "$0")" && pwd)"; PORT="${PHONE_PORT:-8790}"

# Tailscale's CLI is inside the app bundle on macOS and is NOT on PATH by default, so `which
# tailscale` finding nothing does not mean Tailscale is missing. Allow an override for other installs.
TS_BIN="${TAILSCALE_BIN:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
command -v tailscale >/dev/null 2>&1 && TS_BIN="${TAILSCALE_BIN:-$(command -v tailscale)}"

lan_host() { for i in en0 en1; do ip=$(ipconfig getifaddr "$i" 2>/dev/null) && { echo "$ip"; return 0; }; done; return 1; }
ts_host() {
  [ -x "$TS_BIN" ] || return 1
  "$TS_BIN" status --json 2>/dev/null | /usr/bin/python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: raise SystemExit
s = d.get("Self") or {}
print(s.get("DNSName","").rstrip(".") if s.get("Online") else "")' 2>/dev/null
}

if [ "${1:-}" = "--lan" ]; then
  host="$(lan_host)"; where="home Wi-Fi only (forced with --lan)"
else
  host="$(ts_host || true)"
  if [ -n "${host:-}" ]; then
    where="works on cell and Wi-Fi (Tailscale)"
  else
    host="$(lan_host)"
    where="home Wi-Fi only — install Tailscale on the Mac and the phone to use this away from home"
  fi
fi
[ -n "${host:-}" ] || { echo "Could not work out this machine's address."; exit 1; }

# The key is created the first time the server starts, so wait briefly for it.
for _ in $(seq 1 30); do [ -f "$HERE/.token" ] && break; sleep 1; done
[ -f "$HERE/.token" ] || { echo "No access key yet: start the phone line first (bash $HERE/start.sh)."; exit 1; }

echo "https://$host:$PORT/?k=$(cat "$HERE/.token")"
echo "# $where"
