# Voice line upkeep — why your agent stops being strange

Three things run on their own every time the voice line starts. You do not have to do anything, and
there is nothing to configure. This page is here so that when you notice them in the log you know
what they are, and so you can tune them if you want to.

All three exist because of real failures, on a real machine, over months of daily use.

| Guard | Where | What it catches |
|---|---|---|
| **Birth-based session expiry**, 12h | `voice-line/brain.py` | a conversation quietly living for days |
| **Size retirement**, 12 MB | `voice-line/retire-fat-session.sh` | a *heavy* day that hits the context limit in hours |
| **Archive then delete**, 14d / 90d | `voice-line/prune-transcripts.sh` | `~/.claude/projects` silently filling your disk |

---

## The failure these prevent

Your agent is mid-conversation. It goes quiet, loses the thread, and answers the next thing oddly —
as if it forgot what you were doing. You restart it and it is fine.

Nothing crashed. There is nothing in `crash.log`, because no error happened.

What happened is the underlying session hit the model's **context limit** and **force-compacted**:
it summarized itself to make room and carried on with less. That is a normal, healthy mechanism in a
terminal where you can see it happen. On a voice line, where you cannot, it just reads as your agent
going strange.

## Why the session can get that big

The voice line **resumes one session id** on every turn. It has to — without it, each sentence would
start a brand-new conversation and your agent could not remember the sentence before.

So the conversation accumulates. All day, and then the next day.

### Guard 1: expire from the session's birth, not its last turn

There has always been a 12-hour cap. It did not work, because the timestamp was re-stamped on every
save — so the window slid forward every time you spoke and the session could never age out while you
kept using it.

Now the file records `started_at` (birth) separately from `saved_at` (last touch), and expiry
measures birth. Change the window with `SESSION_MAX_AGE_S` in `brain.py`.

### Guard 2: retire on size, because time is the wrong guard on its own

Twelve hours still allows the original failure. A heavy session — long file reads, driving a browser,
converting video — can burn through the context limit in a couple of hours.

**Size predicts compaction. Time does not.** So at start-up, if the stored session's transcript is
already over **12 MB**, the pointer is retired and you begin clean. Tune with `--max-mb`.

> **It only deletes the pointer, never the transcript.** The transcript stays on disk for the pruner.

> **Why it runs at start-up and not whenever:** a running voice line rewrites `.voice_session` on
> every single turn. Deleting that file while the app is up accomplishes nothing — it reappears
> within seconds. It has to happen after the old process is gone and before the new one reads it.

**You lose nothing that matters.** Your memory folder is the memory. The transcript is just the raw
log of how you got there.

### Guard 3: the transcripts themselves

Every Claude Code session writes a `.jsonl` transcript under `~/.claude/projects/`. **Nothing ever
cleans them up.** On the machine this was written on that folder had reached **452 MB**, with one
transcript at 41 MB.

`prune-transcripts.sh` runs on every start and works in two stages, because destroying things in one
step is how you lose work you wanted:

1. **Archive** — idle 14 days: gzip it out of the projects tree into `voice-line/logs/transcript-archive/`.
   Reclaims about 90% of the bytes. Still readable: `gzip -dc <file>.jsonl.gz`
2. **Delete** — archived 90 days: remove the `.gz`.

**Three interlocks, because it deletes files:**

1. Holds any live session — ids from every `.voice_session` on disk plus every UUID on a running
   process's command line.
2. **Aborts if it cannot find a live session at all.** An empty protected list means detection broke,
   not that nothing is live. It refuses to run rather than guess.
3. Hard **7-day floor**. Nothing younger dies, whatever the flags say.

It compresses to the destination and verifies with `gzip -t` **before** removing the source.

---

## Running them by hand

Both live in `voice-line/` and both take `--dry-run`, which prints exactly what would happen and
changes nothing.

```bash
cd voice-line
./prune-transcripts.sh --dry-run                 # preview
./prune-transcripts.sh --archive-days 30         # keep a month before archiving
./retire-fat-session.sh --dry-run                # is my session getting fat?
./retire-fat-session.sh --max-mb 20              # let it run longer before retiring
```

The log is `voice-line/logs/housekeeping.log`.

**First real run on the machine this came from: 452 MB → 190 MB, 261 MB reclaimed, 27 transcripts
archived, zero live sessions touched.**

---

## Two related voice fixes shipped alongside these

Both are in `voice-line/mouth.py`, and both came out of the same kind of silent failure — something
changed and nothing told you.

### Your agent's fallback voice no longer changes its gender

ElevenLabs is the primary voice; Kokoro is the free local fallback. The old fallback default was
`af_heart`, an American **female** voice. So any ElevenLabs hiccup silently swapped the agent's
apparent gender mid-conversation, with nothing on screen to say a fallback had even happened.

The default is now `am_michael` (male), and it is overridable. **Set `KOKORO_VOICE` in
`voice-line/.env` to match your own agent** — Kokoro's voices are prefixed `af_` for female and `am_`
for male. Pick one that sounds like whoever you built.

### An exhausted ElevenLabs quota now heals itself

A 401 used to latch the fallback on **for the rest of the session**. But a dead key and an
**exhausted quota** return the same 401 — and the quota one fixes itself the moment you top up
credits. The latch meant topping up could not recover it; only restarting the voice line could, and
**restarting kills the Claude session running underneath it**, losing your conversation.

Now it backs off for `ELEVEN_RETRY_AFTER_SECONDS` (default 300) and retries, printing a line when
the real voice comes back.

---

## Two bash traps banked here, so you do not pay for them twice

These cost real debugging time while writing the scripts above.

- **Keep comments OUT of `$( )`.** Bash tokenizes quotes while hunting the closing paren, so an
  apostrophe inside a comment within command substitution — *"the process's command line"* — is a
  hard syntax error, reported at the end of the file rather than at the comment.
- **Never use a glob to decide what to delete.** An unmatched glob is fatal in zsh and expands to a
  literal path in bash. Neither is a safe basis for removing files. Use `find`.
- **Syntax-check housekeeping scripts under both shells**, `bash -n` and `zsh -n`. The script above
  passed bash and died in zsh.
