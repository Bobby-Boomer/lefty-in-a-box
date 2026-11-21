# Running a second agent, and the failure nobody sees coming

## The symptom you would notice

**Your second agent reports in, and then sits there. You assume it is working. It is waiting for
you, and nothing tells you the difference.**

That is not a bug in the agent. It is doing exactly what you told it to: check your inbox, report
what you found, then wait. The gap is that **from the outside, "working" and "waiting" look
identical.** No error, no crash, no log entry. Just a terminal that has gone quiet, which is also
what a busy agent looks like.

On the machine this kit came from, that cost five hours. A second agent booted in the morning,
listed its queue, and waited. Nine finished videos sat on disk the whole time. It only surfaced
because the owner happened to ask an unrelated question.

**Two agents who cannot hand work to each other are not a team. They are two tools you operate by
hand.** This page is the other half of spinning up a second agent.

## What ships here

| Piece | What it does |
|---|---|
| `agent-bus/` | the shared inbox. A message is a markdown file. |
| `bin/bus.sh` | send / check / read / reply / done / block / list |
| `bin/agent-watch.sh` | every 5 minutes: escalations, stalled sessions, **and unworked queues** |
| `bin/claude-job-env.sh` | lets the watcher keep running after your interactive login expires |

**No server, no database, nothing to keep alive.** Agents cannot type into each other's terminals,
but they all read and write the same disk, so the disk is the channel.

## Setting it up

```sh
# 1. point the bus somewhere OUTSIDE ~/Documents (see the warning below)
export LEFTY_BUS_DIR="$HOME/.agent-bus"      # this is already the default

# 2. name your project-manager agent
mkdir -p "$HOME/.agent-bus"
echo "agent" > "$HOME/.agent-bus/.pm"        # use your agent's inbox name

# 3. every agent sets its own name, once per session, in its boot file
export BUS_AGENT=editor
"$HOME/<install>/bin/bus.sh" check
```

Then add those last two lines **to each agent's boot file**, so checking the inbox is the first
thing it does. An inbox nobody opens is just a folder.

### Turning on the watcher (macOS only)

```sh
sed "s|__BIN__|$HOME/<install>/bin|" bin/com.agentbus.watch.plist.template \
  > ~/Library/LaunchAgents/com.agentbus.watch.plist
launchctl load ~/Library/LaunchAgents/com.agentbus.watch.plist
```

> [!note] **The watcher is macOS-only; the bus is not.** `agent-watch.sh` is scheduled by launchd.
> **The bus itself works anywhere, including Windows under Git Bash** — it is files and a shell
> script. On Windows you get the mailbox but not the nagging, until someone wires up Task Scheduler.

## How the watcher decides to bother you

It checks three things every five minutes.

1. **Anything escalated** with `bus block` — straight to you, it needs a human.
2. **A session that has gone quiet** mid-task for 3 hours — wedged or finished, either way worth knowing.
3. **An agent sitting on unworked mail** for more than an hour — the failure at the top of this page.

**Number 3 goes to your PM agent first, not to you.** An unworked queue is the manager's job to
chase. You only hear about it if the PM was told and still has not cleared it:

```
agent idle with mail  →  60 min  →  ping the PM
PM does nothing       →  240 min →  notify you (desktop + phone)
```

> [!important] **The escalation measures from WHEN THE PM WAS TOLD, not from how old the message is.**
> This is deliberate and it was wrong the first time. Measuring raw age means that on any pre-existing
> backlog every item is already days old, so the very first run fires a notification per agent, all at
> once. Worse, it answers the wrong question. **You do not need telling that a queue is old. You need
> telling that your manager was asked to deal with it and did not.**

Tune with `HANDOFF_STALE_MINUTES` and `HANDOFF_ESCALATE_MINUTES`.

Phone notifications go through `voice-line/notify.py`, so they land wherever you configured that —
see [push-notifications.md](push-notifications.md).

## The three rules that keep it working

1. **Check the inbox at session start and after every chunk of work.** Nothing pushes.
2. **Answer `needs: reply` before starting anything new.** Another agent is parked on you.
3. **`bus block` instead of guessing.** Money, outbound messages, anything irreversible — escalate.

## Adding an agent: three things, every time

Miss one and the new agent is invisible to the rest:

1. **An inbox** — created automatically the first time anyone sends to that name.
2. **A row in `agent-bus/agents.md`.**
3. **A bus check in its boot file.**

## Why `BUS_AGENT` has no default

Because the version that had one was quietly wrong. It defaulted to the first agent's name, which is
correct on exactly one machine. A second agent that forgot to set it would file its mail under
someone else's name and never see a reply — **the same class of silent failure this whole page is
about.** It now refuses to run and tells you what to set.
