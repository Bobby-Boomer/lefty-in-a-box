#!/bin/bash
# The last step of setup — macOS and Linux.
#
#   bash install/finish-setup.sh [--force]
#
# Writes agent.md at the repo root from install/agent-boot.md. That file is the
# switch: while it is missing, CLAUDE.md sends Claude to the setup wizard; once
# it exists, Claude boots as their agent instead.
#
# WHY IT IS A SEPARATE FILE AND NOT JUST CLAUDE.md: CLAUDE.md is tracked by git,
# so rewriting it in place would make the next `git pull` fail with "local
# changes would be overwritten". agent.md is gitignored, belongs to the member,
# and survives every update.
#
# Safe to run again. It will not clobber an agent.md they have edited unless you
# pass --force.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/install/agent-boot.md"
AGENT="$ROOT/agent.md"
FORCE="${1:-}"

if [ ! -f "$TEMPLATE" ]; then
  echo "  Missing $TEMPLATE — cannot write the agent boot file."
  exit 1
fi

if [ -f "$AGENT" ] && [ "$FORCE" != "--force" ]; then
  echo "  agent.md is already here, leaving it alone (it may have your edits)."
  echo "  To replace it with a fresh copy:  bash install/finish-setup.sh --force"
  exit 0
fi

# The template opens with a note explaining what it is. Everything up to and
# including the first bare --- is that note, and it must not ship to the agent.
awk 'found { print; next } /^---$/ { found = 1 }' "$TEMPLATE" \
  | sed '/./,$!d' > "$AGENT" || { echo "  Could not write $AGENT"; exit 1; }

if [ ! -s "$AGENT" ]; then
  echo "  Wrote an empty agent.md — the template has no --- divider. Not safe."
  rm -f "$AGENT"
  exit 1
fi

NAME="Lefty"
CONFIG="$ROOT/lefty.config.json"
if [ -f "$CONFIG" ]; then
  FOUND="$(python3 -c '
import json,sys
try:
    print((json.load(open(sys.argv[1])).get("name") or "").strip())
except Exception:
    print("")
' "$CONFIG" 2>/dev/null)"
  [ -n "$FOUND" ] && NAME="$FOUND"
fi

echo ""
echo "  Setup is finished. This folder is $NAME now, not an installer."
echo "  agent.md is the file they read at boot — it is yours, edit it any time."
echo ""
