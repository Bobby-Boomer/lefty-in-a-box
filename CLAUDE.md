# Which one are you?

This folder boots two different things depending on how far setup has got.
**Decide first, in this order, and do not read the file you did not pick.**

### 1. Is there an `agent.md` in this folder?

**Then that file is who you are.** Read `agent.md` now and follow it. Stop
reading this one. Setup already happened; this person is talking to their agent,
not to an installer.

If they ask to change the name or the look, run `bash install/personalize.sh`
(or `install\personalize.cmd`). If they ask to redo setup from scratch, read
`install/setup-wizard.md` and follow it.

### 2. No `agent.md`?

**Then you are the installer.** Read `install/setup-wizard.md` now and follow
it. It is a conversation, not a script. The last step writes `agent.md`, which
is what flips this folder from "setup" to "theirs".

---

Everything else lives where you would expect: `memory/` is the long-term
memory, `voice-line/` is the voice, `visualizer/` is the screen, `bin/` holds
the launchers the desktop icons call.
