#!/bin/bash
# prune-transcripts.sh — keep ~/.claude/projects from quietly eating the disk.
#
# WHY THIS EXISTS
#   Every Claude Code session writes a .jsonl transcript under ~/.claude/projects/.
#   Nothing ever cleans them up. On the machine this was written on that folder
#   had reached 452 MB, with a single transcript at 41 MB — months of voice line
#   conversations nobody was ever going to re-read.
#
#   The voice line makes it worse than normal use, because it RESUMES one session
#   id so your agent remembers the sentence before. That is the right behaviour,
#   but it means one conversation can run for days and grow without limit.
#
# THE FRAMEWORK — archive, then delete. Never destroy in one step.
#   Stage 1 (ARCHIVE_DAYS):  gzip the transcript and move it OUT of the projects
#                            tree into ARCHIVE_DIR. Reclaims ~90% of the bytes
#                            and the history is still readable: gzip -dc file.gz
#   Stage 2 (DELETE_DAYS):   delete the .gz. By then nobody is resuming it.
#
# THREE THINGS IT WILL NEVER TOUCH
#   1. Any session id named in a live .voice_session file.
#   2. Any session id on the command line of a running process.
#   3. Anything newer than MIN_AGE_DAYS, even if the flags say otherwise.
#
#   usage: ./prune-transcripts.sh [--dry-run] [--archive-days N] [--delete-days N]
#
# Called automatically on every voice line start from start.sh. Run it with
# --dry-run first if you want to see what it would move before it moves anything.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECTS_DIR="$HOME/.claude/projects"
ARCHIVE_DIR="$SCRIPT_DIR/logs/transcript-archive"
LOG="$SCRIPT_DIR/logs/housekeeping.log"

ARCHIVE_DAYS=14     # gzip + move out of the projects tree after this long idle
DELETE_DAYS=90      # delete the .gz after this long
MIN_AGE_DAYS=7      # hard floor. Nothing younger than this dies, period.

DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)       DRY_RUN=1; shift ;;
        --archive-days)  ARCHIVE_DAYS="$2"; shift 2 ;;
        --delete-days)   DELETE_DAYS="$2"; shift 2 ;;
        -h|--help)       sed -n '2,27p' "$0"; exit 0 ;;
        *)               echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

# Enforce the floor rather than trusting the caller.
if [ "$ARCHIVE_DAYS" -lt "$MIN_AGE_DAYS" ]; then
    ARCHIVE_DAYS="$MIN_AGE_DAYS"
fi

[ -d "$PROJECTS_DIR" ] || { echo "no projects dir at $PROJECTS_DIR"; exit 0; }
mkdir -p "$ARCHIVE_DIR" "$(dirname "$LOG")"

say() { echo "$*"; [ "$DRY_RUN" -eq 1 ] || echo "$(date '+%Y-%m-%dT%H:%M:%S')  $*" >> "$LOG"; }

# ── Build the protected list ────────────────────────────────────────────────
# Session ids that are live right now and must survive regardless of age.

UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# NOTE: keep comments OUT of the $( ) blocks below. Bash tokenizes quotes while
# hunting the closing paren, so an apostrophe inside a comment there (as in
# "the process's command line") is a hard syntax error. Cost a debug cycle once.

# Source 1 — every .voice_session file in or near this install.
# Located with find, not a glob: an unmatched glob is fatal in zsh and expands
# to a literal path in bash, and neither is a safe basis for deleting files.
sessions_from_files="$(
    find "$SCRIPT_DIR" "$SCRIPT_DIR/.." "$HOME" -maxdepth 2 -name '.voice_session' -type f 2>/dev/null \
        | sort -u \
        | while IFS= read -r f; do
            sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f"
        done
)"

# Source 2 — every UUID on the command line of any running process. One strict
# pattern, not a loose --resume match: a loose [0-9a-f-]{36} can begin
# mid-string and emit garbage such as two ids concatenated. UUIDs cover the
# --resume ids anyway, and this over-protects rather than under-protects.
sessions_from_procs="$(ps -eo command= 2>/dev/null | grep -oE "$UUID_RE")"

PROTECTED="$(printf '%s\n%s\n' "$sessions_from_files" "$sessions_from_procs" \
    | grep -xE "$UUID_RE" \
    | sort -u)"

protected_count=$(echo "$PROTECTED" | grep -c . || true)

# An empty protected list means the detection broke, not that nothing is live.
# Refuse to run rather than archive the session someone is mid-conversation on.
if [ "$protected_count" -eq 0 ]; then
    echo "ABORT: could not identify any live session. Refusing to prune." >&2
    echo "$(date '+%Y-%m-%dT%H:%M:%S')  ABORT: protected list empty, pruned nothing" >> "$LOG"
    exit 1
fi

is_protected() {
    [ -n "$PROTECTED" ] && echo "$PROTECTED" | grep -qxF "$1"
}

human() {
    awk -v b="$1" 'BEGIN{
        split("B KB MB GB", u, " "); i=1
        while (b >= 1024 && i < 4) { b /= 1024; i++ }
        printf (i==1 ? "%d %s" : "%.1f %s"), b, u[i]
    }'
}

before_bytes=$(du -sk "$PROJECTS_DIR" 2>/dev/null | awk '{print $1*1024}')

say "--- run start (archive>${ARCHIVE_DAYS}d, delete>${DELETE_DAYS}d, dry_run=$DRY_RUN, protected=$protected_count)"
while IFS= read -r p; do
    [ -n "$p" ] && say "HOLD  $p"
done <<< "$PROTECTED"

# ── Stage 1: archive idle transcripts ───────────────────────────────────────

archived=0; skipped=0

while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f" .jsonl)"

    if is_protected "$base"; then
        say "SKIP  live session  $base"
        skipped=$((skipped+1))
        continue
    fi

    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
    # Namespace the archive by project dir so two projects cannot collide.
    proj="$(basename "$(dirname "$f")")"
    dest="$ARCHIVE_DIR/$proj"
    out="$dest/$base.jsonl.gz"

    if [ "$DRY_RUN" -eq 1 ]; then
        say "WOULD ARCHIVE  $proj/$base  ($(human "$size"))"
        archived=$((archived+1))
        continue
    fi

    mkdir -p "$dest"
    # Compress to the destination FIRST, verify it, and only then drop the source.
    if gzip -c "$f" > "$out" 2>/dev/null && gzip -t "$out" 2>/dev/null; then
        gz=$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out" 2>/dev/null || echo 0)
        rm -f "$f"
        say "ARCHIVED  $proj/$base  $(human "$size") -> $(human "$gz")"
        archived=$((archived+1))
    else
        rm -f "$out"
        say "FAILED to archive $proj/$base — left in place"
    fi
done < <(find "$PROJECTS_DIR" -name '*.jsonl' -type f -mtime +"$ARCHIVE_DAYS" 2>/dev/null)

# ── Stage 2: delete long-dead archives ──────────────────────────────────────

deleted=0

while IFS= read -r f; do
    [ -n "$f" ] || continue
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
    if [ "$DRY_RUN" -eq 1 ]; then
        say "WOULD DELETE  $(basename "$f")  ($(human "$size"))"
    else
        rm -f "$f" && say "DELETED  $(basename "$f")  ($(human "$size"))"
    fi
    deleted=$((deleted+1))
done < <(find "$ARCHIVE_DIR" -name '*.jsonl.gz' -type f -mtime +"$DELETE_DAYS" 2>/dev/null)

# Clear out any project subfolders the deletions emptied.
[ "$DRY_RUN" -eq 1 ] || find "$ARCHIVE_DIR" -type d -empty -delete 2>/dev/null

# ── Report ──────────────────────────────────────────────────────────────────

after_bytes=$(du -sk "$PROJECTS_DIR" 2>/dev/null | awk '{print $1*1024}')
reclaimed=$((before_bytes - after_bytes))
[ "$reclaimed" -lt 0 ] && reclaimed=0

if [ "$archived" -eq 0 ] && [ "$deleted" -eq 0 ]; then
    say "nothing to do. projects dir $(human "$before_bytes"), $protected_count live session(s) held."
else
    say "archived=$archived deleted=$deleted skipped=$skipped"
    say "projects dir $(human "$before_bytes") -> $(human "$after_bytes") (reclaimed $(human "$reclaimed"))"
fi
say "--- run end"
exit 0
