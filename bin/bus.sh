#!/bin/zsh
# agent-bus — a shared inbox so your agents can hand work to each other.
#
# Why a file bus: every agent here is a separate Claude Code process with its own
# terminal. One cannot type into another. But they all read and write the same
# disk, so the disk is the channel. No server, no daemon, nothing to keep alive.
#
# WHERE IT LIVES: $HOME/.agent-bus by default, overridable with LEFTY_BUS_DIR.
# Deliberately NOT inside ~/Documents. On macOS, launchd-spawned processes are
# blocked from Documents by privacy protection, so a scheduled watcher could not
# read the bus if it lived there. This bit us on the original build.
#
#   bus send   <to> <subject> [--needs reply|action|fyi] [--from X] [--body "..."]
#   bus check  [agent]              what is waiting for me
#   bus read   <file>               print a message
#   bus reply  <file> "text"        append a reply and archive it
#   bus done   <file> ["note"]      archive without a reply
#   bus block  <file> "why"         escalate to you, fires a notification
#   bus list                        everything open, all agents
#
# Message status lives in the file. Archiving is a move, so "open" is just
# "still sitting in an inbox".

set -u
BUS="${LEFTY_BUS_DIR:-$HOME/.agent-bus}"

# WHO AM I. There is deliberately NO default here. The original version defaulted
# to the first agent's name, which is fine on the machine it was written for and
# quietly wrong everywhere else: a second agent that forgot to set this would file
# its mail under someone else's name and never see a reply. Fail loudly instead.
ME="${BUS_AGENT:-}"
if [[ -z "$ME" ]]; then
  echo "bus: BUS_AGENT is not set, so I do not know who you are." >&2
  echo "     Set it to your agent's name first, e.g.  export BUS_AGENT=editor" >&2
  echo "     Your name comes from YOUR folder's agent.md, never guessed." >&2
  exit 2
fi

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1 }
[[ $# -ge 1 ]] || usage
CMD="$1"; shift

slug() { print -r -- "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40 }

case "$CMD" in

send)
  [[ $# -ge 2 ]] || { echo "usage: bus send <to> <subject> [--needs X] [--from X] [--body ...]"; exit 1 }
  TO="$1"; SUBJECT="$2"; shift 2
  NEEDS="action"; FROM="$ME"; BODY=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --needs) NEEDS="$2"; shift 2 ;;
      --from)  FROM="$2";  shift 2 ;;
      --body)  BODY="$2";  shift 2 ;;
      *) BODY="$BODY$1"; shift ;;
    esac
  done
  mkdir -p "$BUS/inbox/$TO"
  STAMP="$(date '+%Y-%m-%dT%H%M%S')"
  F="$BUS/inbox/$TO/${STAMP}--${FROM}--$(slug "$SUBJECT").md"
  # Read body from stdin when not given inline, so long messages are easy.
  if [[ -z "$BODY" && ! -t 0 ]]; then BODY="$(cat)"; fi
  {
    print -r -- "---"
    print -r -- "from: $FROM"
    print -r -- "to: $TO"
    print -r -- "created: $(date '+%Y-%m-%d %H:%M:%S')"
    print -r -- "needs: $NEEDS"
    print -r -- "status: open"
    print -r -- "---"
    print -r -- ""
    print -r -- "# $SUBJECT"
    print -r -- ""
    print -r -- "$BODY"
  } > "$F"
  echo "sent -> $F"
  ;;

check)
  WHO="${1:-$ME}"
  D="$BUS/inbox/$WHO"
  [[ -d "$D" ]] || { echo "no inbox for $WHO"; exit 0 }
  N=$(print -rl -- "$D"/*.md(N) | grep -c . )
  if [[ "$N" == "0" ]]; then echo "inbox clear for $WHO"; exit 0; fi
  echo "$N waiting for $WHO:"
  for f in "$D"/*.md(N); do
    SUB=$(grep -a -m1 '^# ' "$f" | sed 's/^# //')
    FROM=$(grep -a -m1 '^from:' "$f" | sed 's/^from: //')
    NEEDS=$(grep -a -m1 '^needs:' "$f" | sed 's/^needs: //')
    printf '  [%s] %-28s %s\n     %s\n' "$NEEDS" "from $FROM" "$SUB" "$f"
  done
  ;;

read)
  [[ $# -ge 1 ]] || { echo "usage: bus read <file>"; exit 1 }
  cat "$1"
  ;;

reply)
  [[ $# -ge 2 ]] || { echo "usage: bus reply <file> \"text\""; exit 1 }
  F="$1"; TEXT="$2"
  [[ -f "$F" ]] || { echo "no such message: $F"; exit 1 }
  ORIG_FROM=$(grep -m1 '^from:' "$F" | sed 's/^from: //')
  {
    print -r -- ""
    print -r -- "---"
    print -r -- ""
    print -r -- "## Reply from $ME — $(date '+%Y-%m-%d %H:%M:%S')"
    print -r -- ""
    print -r -- "$TEXT"
  } >> "$F"
  # The reply goes back to the sender's inbox so they actually see it.
  SUB=$(grep -m1 '^# ' "$F" | sed 's/^# //')
  mkdir -p "$BUS/inbox/$ORIG_FROM"
  STAMP="$(date '+%Y-%m-%dT%H%M%S')"
  R="$BUS/inbox/$ORIG_FROM/${STAMP}--${ME}--re-$(slug "$SUB").md"
  {
    print -r -- "---"
    print -r -- "from: $ME"
    print -r -- "to: $ORIG_FROM"
    print -r -- "created: $(date '+%Y-%m-%d %H:%M:%S')"
    print -r -- "needs: fyi"
    print -r -- "status: open"
    print -r -- "---"
    print -r -- ""
    print -r -- "# Re: $SUB"
    print -r -- ""
    print -r -- "$TEXT"
  } > "$R"
  mkdir -p "$BUS/archive"
  mv "$F" "$BUS/archive/"
  echo "replied to $ORIG_FROM -> $R"
  echo "archived original"
  ;;

done)
  [[ $# -ge 1 ]] || { echo "usage: bus done <file> [note]"; exit 1 }
  F="$1"; NOTE="${2:-}"
  [[ -f "$F" ]] || { echo "no such message: $F"; exit 1 }
  if [[ -n "$NOTE" ]]; then
    { print -r -- ""; print -r -- "## Closed by $ME — $(date '+%Y-%m-%d %H:%M:%S')"; print -r -- ""; print -r -- "$NOTE" } >> "$F"
  fi
  mkdir -p "$BUS/archive"; mv "$F" "$BUS/archive/"
  echo "archived $F"
  ;;

block)
  [[ $# -ge 2 ]] || { echo "usage: bus block <file> \"why\""; exit 1 }
  F="$1"; WHY="$2"
  [[ -f "$F" ]] || { echo "no such message: $F"; exit 1 }
  { print -r -- ""; print -r -- "## BLOCKED — needs the owner, flagged by $ME $(date '+%Y-%m-%d %H:%M:%S')"; print -r -- ""; print -r -- "$WHY" } >> "$F"
  mkdir -p "$BUS/blocked"; mv "$F" "$BUS/blocked/"
  /usr/bin/osascript -e "display notification \"$WHY\" with title \"Agent blocked — needs you\" sound name \"Glass\"" >/dev/null 2>&1
  echo "escalated to the owner: $BUS/blocked/$(basename "$F")"
  ;;

list)
  echo "=== open, by inbox ==="
  for d in "$BUS"/inbox/*(N/); do
    who=$(basename "$d")
    n=$(print -rl -- "$d"/*.md(N) | grep -c . )
    printf '  %-10s %s\n' "$who" "$n"
  done
  b=$(print -rl -- "$BUS"/blocked/*.md(N) | grep -c . )
  echo "=== blocked, waiting on you: $b ==="
  for f in "$BUS"/blocked/*.md(N); do
    printf '  %s\n' "$(grep -a -m1 '^# ' "$f" | sed 's/^# //')"
  done
  ;;

*) usage ;;
esac
