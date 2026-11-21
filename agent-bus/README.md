# The agent bus

A shared inbox so your agents can hand work to each other without going through you.

**Why it exists.** Every agent is a separate Claude Code process in its own terminal. One cannot type
into another. But they all read and write the same disk, so **the disk is the channel.** No server,
no daemon, nothing that has to stay alive. A message is a markdown file. Archiving it is a move.

**Where it lives:** `~/.agent-bus/`, overridable with `LEFTY_BUS_DIR`.

> [!important] **Do not move it into `~/Documents`.** On macOS, scheduled (launchd) processes are
> blocked from Documents by privacy protection. The watcher would read nothing and tell you
> everything was fine.

## The commands

```sh
bus="$HOME/<install>/bin/bus.sh"
export BUS_AGENT=editor          # who YOU are. Set this once per session.

$bus check                     # what is waiting for me
$bus list                      # everything open, everyone
$bus read  <file>
$bus send  editor "Subject" --needs action --body "..."
$bus reply <file> "text"       # replies to the sender, archives the original
$bus done  <file> ["note"]     # close it, no reply needed
$bus block <file> "why"        # escalate to the owner, fires a notification
```

`BUS_AGENT` has **no default on purpose.** An agent that forgets to set it gets a loud error rather
than quietly filing its mail under somebody else's name.

Long messages: pipe them in instead of using `--body`.

```sh
printf '%s\n' "line one" "line two" | $bus send editor "Subject" --needs action
```

## The protocol

**`needs:` says what you want back.**

| value | meaning |
|---|---|
| `fyi` | Read it. No response expected. Close with `done`. |
| `action` | Do the thing. Close with `done`, or `reply` if there is something to report. |
| `reply` | Answer the question. The sender is parked waiting on you. |

**Check your inbox at the start of every session, and again whenever you finish a chunk of work.**
Nothing pushes. If you do not look, you do not see it.

**Answer `reply` messages before starting new work.** Another agent is blocked on you.

**Escalate rather than guess.** If a message needs a decision only the owner can make — spending
money, sending something outbound, anything irreversible — use `bus block`. It moves the message to
`blocked/` and fires a notification. Do not sit on it and do not decide it yourself.

**One message, one job.** Six unrelated asks in one file get half-answered.

> [!warning] **THE FAILURE THIS BUS IS DESIGNED AROUND, learned the hard way.**
> **A handoff that is sent but never picked up looks exactly like work that was never done.**
> An agent that reports in and waits for a reply is indistinguishable, from the outside, from an
> agent that is working. On the machine this came from, a second agent sat idle for five hours with
> finished work on disk because nobody answered it. **That is what `agent-watch.sh` exists to catch
> —** see [docs/second-agent.md](../docs/second-agent.md).

## Who is who

`agents.md` is the roster. **Keep it current.** When an agent is added or retired, update it in the
same session — a roster that lies is worse than no roster, because work gets addressed to nobody.

## Escalation path

```
agent  ->  bus block  ->  blocked/  ->  notification  ->  you
```

**If you do not know who should own something, send it to your PM agent** (the name in
`~/.agent-bus/.pm`, or set `AGENT_PM`). Routing is its job.
