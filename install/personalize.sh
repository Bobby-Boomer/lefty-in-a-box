#!/bin/bash
# Name your agent and pick how it looks — macOS and Linux.
#
#   bash install/personalize.sh
#
# Writes lefty.config.json at the repo root. Everything else reads that file:
# the screen picks up the look, the desktop shortcut gets the name, and the
# agent introduces itself by it.
#
# Safe to run again any time. It shows you what you have now and lets you keep
# it by pressing return.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/lefty.config.json"

# Keep this list in step with LOOKS in visualizer/index.html.
LOOK_KEYS=(rain amber ice violet mono)
LOOK_DESC=(
  "green rain, the original"
  "warm amber, like an old terminal"
  "cold blue, quieter in a dark room"
  "violet"
  "no colour at all, if the rest is distracting"
)

CUR_NAME="Lefty"
CUR_LOOK="rain"
if [ -f "$CONFIG" ]; then
  # Read with python so a hand-edited file with odd spacing still parses.
  read -r CUR_NAME CUR_LOOK <<<"$(python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    d={}
print((d.get("name") or "Lefty"), (d.get("look") or "rain"))
' "$CONFIG" 2>/dev/null || echo "Lefty rain")"
fi

echo ""
echo "=== Make it yours ==="
echo ""

# ── the name ────────────────────────────────────────────────────────────────
echo "  What do you want to call your agent?"
echo "  This is the name it answers to and the name on your desktop icons."
echo ""
printf "  Name [%s]: " "$CUR_NAME"
read -r NAME
NAME="${NAME:-$CUR_NAME}"

# Strip anything that would break a filename or a shell quote. A name is a
# label, not an input to anything clever, so this can be blunt.
NAME="$(printf '%s' "$NAME" | tr -d '"'"'"'\\/:*?<>|$`' | sed 's/^ *//; s/ *$//')"
[ -z "$NAME" ] && NAME="$CUR_NAME"

# ── the look ────────────────────────────────────────────────────────────────
echo ""
echo "  How should the screen look?"
echo ""
i=1
for k in "${LOOK_KEYS[@]}"; do
  mark=" "
  [ "$k" = "$CUR_LOOK" ] && mark="*"
  printf "   %s %d) %-7s %s\n" "$mark" "$i" "$k" "${LOOK_DESC[$((i-1))]}"
  i=$((i+1))
done
echo ""
echo "  You can see any of them before choosing. With the screen running:"
echo "      http://127.0.0.1:8777/?look=amber"
echo ""
printf "  Pick 1-%d [%s]: " "${#LOOK_KEYS[@]}" "$CUR_LOOK"
read -r PICK

LOOK="$CUR_LOOK"
case "$PICK" in
  '') LOOK="$CUR_LOOK" ;;
  *[!0-9]*) echo "  Not a number, keeping $CUR_LOOK." ;;
  *)
    if [ "$PICK" -ge 1 ] && [ "$PICK" -le "${#LOOK_KEYS[@]}" ]; then
      LOOK="${LOOK_KEYS[$((PICK-1))]}"
    else
      echo "  Out of range, keeping $CUR_LOOK."
    fi
    ;;
esac

# ── write it ────────────────────────────────────────────────────────────────
python3 - "$CONFIG" "$NAME" "$LOOK" <<'PY'
import json, sys, os
config, name, look = sys.argv[1], sys.argv[2], sys.argv[3]

# Keep anything else already in the file. A future version may add keys and
# this script must not quietly delete them.
data = {}
if os.path.exists(config):
    try:
        with open(config) as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        pass

data["name"] = name
data["look"] = look

with open(config, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo ""
echo "  Saved."
echo "    Name: $NAME"
echo "    Look: $LOOK"
echo ""

# ── shortcuts, so the icon says the right name ──────────────────────────────
if [ -x "$ROOT/install/shortcuts.sh" ]; then
  echo "  Rebuilding your desktop shortcuts with the new name..."
  bash "$ROOT/install/shortcuts.sh" "$ROOT" >/dev/null 2>&1 \
    && echo "  Done." \
    || echo "  Could not rebuild the shortcuts. Run install/shortcuts.sh yourself."
fi

echo ""
echo "  The screen picks up the new look on its next reload."
echo "  Run this again any time to change either one."
echo ""
