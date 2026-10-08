#!/bin/bash
# retire-fat-session.sh — start a fresh conversation if the stored one has grown
# big enough to risk compacting mid-sentence.
#
# WHY THIS EXISTS
#   brain.py resumes one session id so the voice line remembers what you just
#   said. There is a 12-hour cap on that (SESSION_MAX_AGE_S), but TIME is the
#   wrong guard for this particular failure. A heavy session — long file reads,
#   driving a browser, converting video — can blow through the model's context
#   limit in a couple of hours.
#
#   When that happens mid-conversation the session force-compacts: your agent
#   goes quiet, loses its thread, and answers the next thing strangely. There is
#   nothing in any log to explain it, because nothing crashed.
#
#   SIZE predicts that. Time does not. So at start-up, if the stored session's
#   transcript is already fat, retire the session id and begin clean.
#
#   Nothing of substance is lost: the memory folder is the memory, not the
#   transcript. And the transcript itself is left on disk for prune-transcripts.sh
#   to archive on its normal schedule — this script never deletes history.
#
#   usage: ./retire-fat-session.sh [--dry-run] [--max-mb N]
#
# Called from start.sh BEFORE the app starts. That ordering is required, not
# cosmetic: a running voice line rewrites .voice_session on every single turn,
# so deleting it while the app is up achieves nothing at all.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SESSION_FILE="$SCRIPT_DIR/.voice_session"
PROJECTS_DIR="$HOME/.claude/projects"
LOG="$SCRIPT_DIR/logs/housekeeping.log"

MAX_MB=12       # a 22 MB transcript compacted mid-conversation. Retire earlier.
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --max-mb)  MAX_MB="$2"; shift 2 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *)         echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$(dirname "$LOG")"
say() { echo "$*"; [ "$DRY_RUN" -eq 1 ] || echo "$(date '+%Y-%m-%dT%H:%M:%S')  [session] $*" >> "$LOG"; }

[ -f "$SESSION_FILE" ] || { echo "no stored session — nothing to retire"; exit 0; }

SID="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SESSION_FILE")"
if [ -z "$SID" ]; then
    say "session file unreadable, retiring it so the next start is clean"
    [ "$DRY_RUN" -eq 1 ] || rm -f "$SESSION_FILE"
    exit 0
fi

# Find the transcript by id rather than guessing the project folder name. The
# folder is derived from the working directory, and on a case-insensitive volume
# two spellings of the same path produce two different folder NAMES.
TRANSCRIPT="$(find "$PROJECTS_DIR" -name "$SID.jsonl" -type f 2>/dev/null | head -1)"

if [ -z "$TRANSCRIPT" ]; then
    say "no transcript on disk for ${SID:0:8} — leaving the session alone"
    exit 0
fi

BYTES=$(stat -f%z "$TRANSCRIPT" 2>/dev/null || stat -c%s "$TRANSCRIPT" 2>/dev/null || echo 0)
MB=$(awk -v b="$BYTES" 'BEGIN{printf "%.1f", b/1048576}')
LIMIT=$((MAX_MB * 1048576))

if [ "$BYTES" -lt "$LIMIT" ]; then
    echo "session ${SID:0:8} is ${MB} MB, under the ${MAX_MB} MB limit — keeping it"
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    say "WOULD RETIRE ${SID:0:8} — ${MB} MB over the ${MAX_MB} MB limit"
    exit 0
fi

# Retire the pointer only. prune-transcripts.sh archives the transcript later.
rm -f "$SESSION_FILE"
say "RETIRED ${SID:0:8} — transcript ${MB} MB exceeded ${MAX_MB} MB. Starting a fresh session; transcript left for the pruner."
exit 0
