#!/bin/zsh
# agent-watch — tell you when an agent needs you, has gone quiet, or is sitting
# on work nobody picked up.
#
# Runs every 5 minutes from a launchd job. macOS only: launchd is the scheduler.
# The BUS ITSELF works everywhere, including Windows under Git Bash. Only this
# watcher is Mac-specific, and that is stated plainly rather than hidden.
#
# IMPORTANT: nothing here may live under ~/Documents. launchd-spawned processes
# are blocked from Documents by macOS privacy protection, so a watcher that
# reads a bus in Documents silently reads nothing.
#
# Two things it watches:
#   1. agent-bus/blocked/  — anything escalated to you
#   2. each running agent's session transcript — if it has not moved in a long
#      while, the agent is wedged or finished, and either way you want to know.
#
# It notifies ONCE per condition. State files stop it nagging.

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

. "${0:A:h}/claude-job-env.sh"   # long-lived token for unattended runs; the interactive login expires 2026-11-28 and cannot be renewed

BUS="${LEFTY_BUS_DIR:-$HOME/.agent-bus}"
LOGDIR="${LEFTY_LOG_DIR:-$HOME/.agent-bus/.logs}"
LOG="$LOGDIR/agent-watch.log"
STATE="$LOGDIR/.agent-watch"
# 45 minutes was too twitchy: an agent doing a long piece of work goes quiet
# for longer than that routinely, and it fired hourly all night. 3 hours means
# "this is genuinely stopped", not "this is thinking".
STALL_MINUTES="${AGENT_STALL_MINUTES:-180}"

mkdir -p "$LOGDIR" "$STATE"
say_log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG" }
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" >/dev/null 2>&1 }

# ── 1. anything escalated to you ────────────────────────────────────────────
for f in "$BUS"/blocked/*.md(N); do
  key="$STATE/blocked-$(basename "$f").seen"
  [[ -f "$key" ]] && continue
  SUB=$(grep -m1 '^# ' "$f" | sed 's/^# //')
  FROM=$(grep -m1 '^from:' "$f" | sed 's/^from: //')
  say_log "BLOCKED from $FROM: $SUB"
  notify "Agent blocked — needs you" "$FROM: $SUB"
  : >"$key"
done

# ── 2. agents that have gone quiet ──────────────────────────────────────────
# A Claude session appends to its transcript constantly while it works. A file
# that has not changed in STALL_MINUTES means that agent stopped, one way or
# another. Worth one notification, not a stream of them.
PROJ="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
for d in "$PROJ"/*(N/); do
  # CAREFUL: `ls -t <glob-with-no-matches>` falls back to listing the CURRENT
  # DIRECTORY, so an empty project folder returned "bin" (a subdir of the
  # WorkingDirectory) and the watcher tracked a bogus target. Collect into an
  # array and test it instead of piping a possibly-empty glob into ls.
  # Found 2026-09-19.
  files=( "$d"/*.jsonl(N) )
  (( ${#files} )) || continue
  newest=$(ls -t -- "${files[@]}" | head -1)
  [[ -f "$newest" ]] || continue
  # only care about transcripts touched in the last day; ignore old ones
  find "$newest" -mtime -1 >/dev/null 2>&1 || continue
  [[ -n "$(find "$newest" -mmin -1440 2>/dev/null)" ]] || continue
  if [[ -z "$(find "$newest" -mmin -$STALL_MINUTES 2>/dev/null)" ]]; then
    key="$STATE/stalled-$(basename "$newest").seen"
    [[ -f "$key" ]] && continue
    AGE=$(( ( $(date +%s) - $(stat -f %m "$newest") ) / 60 ))
    say_log "STALLED: $newest quiet for ${AGE}m"
    notify "Agent has gone quiet" "No activity for ${AGE} minutes. Check the terminal."
    : >"$key"
  else
    # it moved again — re-arm so a future stall notifies
    rm -f "$STATE/stalled-$(basename "$newest").seen" 2>/dev/null
  fi
done

# ── 3. handoffs nobody picked up ────────────────────────────────────────────
# WHY THIS EXISTS. A second agent booted, reported its queue, and then waited for a
# reply exactly as its boot file tells it to. Nobody answered. It sat idle for
# five hours while finished work sat on disk, and the only reason it surfaced
# was the owner happening to ask a question. A handoff that is
# sent but never picked up looks EXACTLY like work that was never done.
#
# Sections 1 and 2 above cannot catch this: nothing is blocked, and the agent is
# not stalled mid-task — it is idle and waiting, which looks healthy.
#
# ROUTING. This pings your PROJECT-MANAGER AGENT first, not you. An unworked
# queue is the PM's job to chase. You only hear about it if the PM has not
# cleared it after ESCALATE_MINUTES, and that is the signal worth interrupting
# you for -- not "an agent is behind" but "your PM is not managing".
#
# Set AGENT_PM to the name of your manager agent. With one agent installed it is
# just that agent telling itself, which is still useful: it puts the backlog in
# front of the only agent you have.
PM="${AGENT_PM:-$(cat "$BUS/.pm" 2>/dev/null || echo agent)}"
STALE_MIN="${HANDOFF_STALE_MINUTES:-60}"
ESCALATE_MIN="${HANDOFF_ESCALATE_MINUTES:-240}"

for d in "$BUS"/inbox/*(N/); do
  agent=$(basename "$d")
    # Never nag the PM about the PM. It is the one being told.
  [[ "$agent" == "$PM" || "$agent" == "owner" ]] && continue
  items=( "$d"/*.md(N) )
  (( ${#items} )) || continue

  # Oldest open item decides. Keying state on ITS filename means a fresh
  # notification fires once per genuinely-new backlog, and re-arms by itself
  # the moment that item is replied to or archived.
  oldest=$(ls -tr -- "${items[@]}" | head -1)
  age=$(( ( $(date +%s) - $(stat -f %m "$oldest") ) / 60 ))
  (( age >= STALE_MIN )) || continue

  SUB=$(grep -m1 '^# ' "$oldest" | sed 's/^# //')
  (( ${#items} == 1 )) && plural="item" || plural="items"
  key="$STATE/handoff-$agent-$(basename "$oldest").seen"

  if [[ ! -f "$key" ]]; then
    say_log "STALE HANDOFF: $agent has ${#items} open, oldest ${age}m -- $SUB"
    BUS_AGENT=agentwatch "${0:A:h}/bus.sh" send "$PM" \
      "$agent has ${#items} unworked inbox $plural, oldest is ${age} minutes old" \
      --needs action --from agentwatch \
      --body "Automatic check, not a human. Nothing is blocked and nothing has crashed -- $agent is simply idle with work waiting, which is the state that looks healthy and is not.

Oldest open item: $SUB
Open count: ${#items}
Oldest age: ${age} minutes

As PM: either give $agent the go-ahead, reassign it, or close the item. If it is genuinely parked, reply on it so it stops ageing." >/dev/null 2>&1
    : >"$key"
  fi

  # The PM was told and it is STILL sitting there. Now it is yours to know.
  # MEASURE FROM WHEN THE PM WAS TOLD, not from the item's own age. Measuring
  # absolute age was the first version and it was wrong twice over: on a
  # pre-existing backlog every item is already days old, so the very first run
  # would fire a phone notification per agent at once; and it answers the wrong
  # question. You do not need telling that a queue is old. You need telling
  # that your PM was asked to deal with it and did not.
  esc="$STATE/handoff-esc-$agent-$(basename "$oldest").seen"
  told=0
  [[ -f "$key" ]] && told=$(( ( $(date +%s) - $(stat -f %m "$key") ) / 60 ))
  if (( told >= ESCALATE_MIN )) && [[ ! -f "$esc" ]]; then
    hrs=$(( age / 60 )); toldh=$(( told / 60 ))
    say_log "ESCALATING to the owner: $agent oldest item ${age}m, the PM did not clear it"
    notify "Agent queue not being worked" "$agent: ${#items} open. Your PM was told ${toldh}h ago and has not cleared it."
    /usr/bin/python3 "${0:A:h}/../voice-line/notify.py" \
      "$agent has ${#items} items sitting unworked. Your PM agent was pinged about this ${toldh} hours ago and still has not cleared it. Oldest item has been waiting ${hrs} hours. Top item: $SUB" >/dev/null 2>&1
    : >"$esc"
  fi
done

# Drop state files for items that are gone, so the same filename can notify
# again if it ever comes back. Without this the state dir grows forever and a
# re-sent message would be silently suppressed.
for f in "$STATE"/handoff-*.seen(N); do
  base=${f:t}; base=${base#handoff-}; base=${base#esc-}
  agent=${base%%-*}; fname=${base#*-}; fname=${fname%.seen}
  [[ -f "$BUS/inbox/$agent/$fname" ]] || rm -f "$f"
done

# ── housekeeping ────────────────────────────────────────────────────────────
find "$LOGDIR" -name 'agent-watch.log' -mtime +14 -delete 2>/dev/null
exit 0
