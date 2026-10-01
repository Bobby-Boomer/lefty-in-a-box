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

# Make memory/ a real Obsidian vault, every time, no questions asked.
#
# WHY THIS IS HERE AND NOT ONLY IN THE WIZARD: step 6c of setup-wizard.md tells
# the installer to run install/obsidian.sh. It got skipped on the live Windows
# install with Tijo on 2026-09-24, and skipped AGAIN with Leigh Anne on
# 2026-10-01. Twice is not bad luck, it is a design fault: the vault depended on
# a conversation remembering a step. Now the script that must run anyway does it.
#
# --vault-only installs NOTHING. It writes .obsidian config inside a folder the
# member already owns, so the hard rule is untouched. The app itself stays an
# explicit, asked-for choice back in step 6c.
if [ -x "$ROOT/install/obsidian.sh" ] || [ -f "$ROOT/install/obsidian.sh" ]; then
  bash "$ROOT/install/obsidian.sh" --vault-only >/dev/null 2>&1 \
    && echo "  memory/ is set up as an Obsidian vault." \
    || echo "  Could not set up the Obsidian vault. Run: bash install/obsidian.sh --vault-only"
fi

echo ""
echo "  Setup is finished. This folder is $NAME now, not an installer."
echo "  agent.md is the file they read at boot — it is yours, edit it any time."
echo ""
