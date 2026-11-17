#!/bin/bash
# icloud-guard.sh — put iCloud-offloaded files back on disk before the agent boots. macOS only.
#
# THE SYMPTOM YOU WOULD NOTICE (found 2026-11-17):
# Lefty boots with no name, no rules and no memory of your system — a blank assistant. Claude Code
# reports CLAUDE.md as MISSING. Browser control dies with "Unknown system error -11". Memory files
# read as empty. Nothing was deleted and nothing is corrupted: if your install lives in iCloud Drive
# and macOS has "Optimize Mac Storage" on, iCloud pulled the bytes off your disk when space got tight
# and left a stub behind. Reading a stub with iCloud unreachable fails with EDEADLK,
# "Resource deadlock avoided", which surfaces as error -11.
#
# It came back the SAME DAY it was first repaired by hand, which is why this runs every session
# instead of once.
#
# TWO TRAPS, both learned the hard way:
#   1. `brctl download <folder>` does NOT download the files inside it. Per file only.
#   2. The `dataless` flag can linger after `brctl download` returns. Force a real read, then check
#      the flag a SECOND time. Proving brctl ran is not proving the file is on disk.
#
# WIRE IT UP as a SessionStart hook in ~/.claude/settings.json:
#   "hooks": { "SessionStart": [ { "hooks": [
#       { "type": "command", "command": "bash /path/to/bin/icloud-guard.sh", "timeout": 120 } ] } ] }

set -uo pipefail

# -flags is BSD find. Nothing to do anywhere else.
[ "$(uname -s)" = "Darwin" ] || exit 0
command -v brctl >/dev/null 2>&1 || exit 0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

LOG="${LEFTY_LOG_DIR:-$ROOT/logs}/icloud-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

# The critical set: identity, tooling, memory. Single files first.
# NOTE: macOS ships bash 3.2, where "${ARR[@]}" on an empty array trips set -u.
# ${ARR[@]+"${ARR[@]}"} is the form that survives it.
files=()
[ -f "$HOME/CLAUDE.md" ] && files+=("$HOME/CLAUDE.md")
[ -f "$ROOT/CLAUDE.md" ] && files+=("$ROOT/CLAUDE.md")
[ -f "$ROOT/agent.md" ] && files+=("$ROOT/agent.md")

# KEEP THIS LIST NARROW. Point it at identity, tools and memory — never a whole working folder.
# On the machine this was written for, the working folder held ~126,000 files that are SUPPOSED to
# stay offloadable (node_modules, media, renders). Pinning those would fill the disk, which is the
# very thing that caused the offloading.
dirs=()
[ -d "${LEFTY_MEMORY_DIR:-$ROOT/memory}" ] && dirs+=("${LEFTY_MEMORY_DIR:-$ROOT/memory}")
for sub in bin skills install voice-line/prompts; do
  [ -d "$ROOT/$sub" ] && dirs+=("$ROOT/$sub")
done

offloaded=()
for f in ${files[@]+"${files[@]}"}; do
  if [ -n "$(find "$f" -maxdepth 0 -flags +dataless 2>/dev/null)" ]; then
    offloaded+=("$f")
  fi
done
for d in ${dirs[@]+"${dirs[@]}"}; do
  while IFS= read -r -d '' f; do
    offloaded+=("$f")
  done < <(find "$d" -type f -flags +dataless -print0 2>/dev/null)
done

count=${#offloaded[@]}
stamp="$(date '+%Y-%m-%d %H:%M:%S')"

if [ "$count" -eq 0 ]; then
  echo "$stamp  clean — nothing offloaded in the critical set" >>"$LOG"
  exit 0
fi

# Request each file, then force a real read. brctl alone can leave the flag set.
for f in ${offloaded[@]+"${offloaded[@]}"}; do
  brctl download "$f" >/dev/null 2>&1
done
for f in ${offloaded[@]+"${offloaded[@]}"}; do
  head -c 1 "$f" >/dev/null 2>&1
done

# Verify. A second dataless check is the only thing that proves it.
still=0
for f in ${offloaded[@]+"${offloaded[@]}"}; do
  if [ -n "$(find "$f" -maxdepth 0 -flags +dataless 2>/dev/null)" ]; then
    still=$((still + 1))
    echo "$stamp  STILL OFFLOADED: $f" >>"$LOG"
  fi
done

restored=$((count - still))
echo "$stamp  found $count offloaded, restored $restored, failed $still" >>"$LOG"
# Name them. Without this the log gives you a count and nothing you can act on.
for f in ${offloaded[@]+"${offloaded[@]}"}; do
  echo "$stamp    + $f" >>"$LOG"
done

if [ "$still" -gt 0 ]; then
  echo "iCloud guard: restored $restored files, $still STILL OFFLOADED — see $LOG" >&2
  echo "iCloud may be signed out or offline. Check System Settings > Apple Account > iCloud." >&2
  exit 1
fi

echo "iCloud guard: restored $restored offloaded files (identity/tools/memory)." >&2
exit 0
