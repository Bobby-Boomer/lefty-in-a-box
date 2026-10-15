#!/bin/bash
# Scheduled reminders — your agent texts you on Telegram when something is due.
#
# WHY THIS EXISTS, and why it is not just a note in memory:
#
# An agent promises you a reminder in conversation, the conversation ends, and
# the reminder dies with it. Nothing about a chat session survives to fire later.
# There is no background process in a terminal that has been closed.
#
# So the clock lives on disk, outside the agent, and something in the operating
# system wakes it up. That is the whole idea. The agent writes a line to a file;
# the file outlives the conversation.
#
# WHAT IT NEEDS
#   ~/.agent-telegram/token             the BotFather token (see telegram/README.md)
#   ~/.agent-telegram/allowed_chat_id   written when you first pair your phone
# Both are the same files telegram/bridge.py uses. Set the bridge up first.
#
# THE QUEUE — telegram/reminders.tsv, next to this script:
#
#   due<TAB>repeat_days<TAB>message
#
#   due          YYYY-MM-DD, the next date this should fire
#   repeat_days  0  = one-shot; the line is deleted once it fires
#                N  = recurring; re-armed N days out
#   message      what you read on your phone
#
# Lines starting with # are comments. Edit by hand any time — nothing caches it,
# and nothing needs restarting.
#
# RUN IT ONCE A DAY. macOS: see telegram/com.agent.remind.plist for a launchd job.
# Linux: a crontab line, `0 9 * * * /path/to/telegram/remind.sh`.
# Windows: Task Scheduler, daily, running this through Git Bash or WSL.
#
# Test without waiting for tomorrow: add a line dated today and run the script.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="$HERE/reminders.tsv"
LOG="$HERE/remind.log"
CONF="$HOME/.agent-telegram"
TOKEN_FILE="$CONF/token"
CHAT_FILE="$CONF/allowed_chat_id"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

say_log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# Telegram send. Returns non-zero on any failure so the caller can keep the
# line armed rather than silently dropping a reminder.
tg() {
  if [ ! -s "$TOKEN_FILE" ]; then say_log "no token at $TOKEN_FILE"; return 1; fi
  if [ ! -s "$CHAT_FILE" ]; then say_log "not paired yet, no $CHAT_FILE"; return 1; fi
  local t c
  t=$(tr -d '[:space:]' < "$TOKEN_FILE")
  c=$(tr -d '[:space:]' < "$CHAT_FILE")
  curl -s --max-time 20 -X POST "https://api.telegram.org/bot${t}/sendMessage" \
    -d chat_id="$c" --data-urlencode "text=$1" | grep -q '"ok":true'
}

# date + N days, portable across BSD (macOS) and GNU (Linux) date.
days_from_today() {
  date -j -v+"$1"d '+%Y-%m-%d' 2>/dev/null || date -d "+$1 days" '+%Y-%m-%d'
}

if [ ! -s "$FILE" ]; then say_log "no queue at $FILE"; exit 0; fi

TODAY=$(date '+%Y-%m-%d')
TAB=$(printf '\t')
TMP="${FILE}.tmp.$$"
: >"$TMP"
FIRED=0

# NOTE: every rewrite below uses "$TAB", never a \t escape. Some shells' print
# and echo builtins do not expand escapes, which writes a literal backslash-t
# and corrupts the queue on the first run. Found in testing, 2026-10-15.
emit() { printf '%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" >>"$TMP"; }

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|'#'*) printf '%s\n' "$line" >>"$TMP"; continue ;;
  esac

  due="${line%%$TAB*}"
  rest="${line#*$TAB}"
  repeat="${rest%%$TAB*}"
  msg="${rest#*$TAB}"

  if [ "$due" = "$line" ] || [ -z "$msg" ]; then
    say_log "malformed line kept as-is: $line"
    printf '%s\n' "$line" >>"$TMP"
    continue
  fi

  # Not due yet. String compare is correct for zero-padded ISO dates.
  if [ "$due" \> "$TODAY" ]; then
    emit "$due" "$repeat" "$msg"
    continue
  fi

  # Due today, or overdue because the machine was asleep on the day. Either
  # way it fires now rather than being missed.
  if tg "Reminder: $msg"; then
    say_log "fired: $msg"
    FIRED=$((FIRED + 1))
  else
    say_log "SEND FAILED, line stays armed: $msg"
    emit "$due" "$repeat" "$msg"
    continue
  fi

  if [ "$repeat" = "0" ]; then
    say_log "one-shot, removed: $msg"
  else
    # Re-arm from TODAY, not from the old due date. Otherwise an overdue
    # recurring reminder fires every single day until it catches up.
    NEXT=$(days_from_today "$repeat")
    emit "$NEXT" "$repeat" "$msg"
    say_log "re-armed for $NEXT: $msg"
  fi
done < "$FILE"

mv "$TMP" "$FILE"
say_log "run complete, $FIRED fired"
