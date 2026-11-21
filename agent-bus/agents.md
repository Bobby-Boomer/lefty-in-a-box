# The roster

Every agent that exists on this machine, what it owns, and how to reach it.

**Keep this current.** When an agent is spun up or retired, update this file in the same session.
A roster that lies is worse than none, because work gets addressed to an inbox nobody reads.

| agent | inbox name | owns | boot file |
|---|---|---|---|
| *(your agent)* | `agent` | everything, for now | `agent.md` in the install folder |

## The PM

One agent is the **project manager**: anything with no obvious owner routes to it, and the watcher
reports unworked queues to it before bothering you.

Set it once:

```sh
echo "agent" > ~/.agent-bus/.pm      # use your PM agent's inbox name
```

With a single agent installed this is just that agent telling itself, which is still worth having:
it puts the backlog in front of the only agent you have.

## Adding a second agent

Three things, every time. Miss one and the new agent is invisible to the others:

1. **An inbox** — created automatically the first time anyone sends to that name.
2. **A row in this table.**
3. **A bus check in its boot file**, so it looks at its inbox at session start.

Full walkthrough: [docs/second-agent.md](../docs/second-agent.md).
