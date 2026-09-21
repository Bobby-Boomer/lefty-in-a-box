# Memory

**This folder is your agent's long-term memory.** Plain markdown files on your own computer. Nothing
here is uploaded anywhere.

Your agent reads these at the start of every conversation and writes to them as you work. That is the
whole trick. It is not a clever model, it is a model that took notes.

## What is in here

| File | What it holds |
|---|---|
| [[Business]] | What you do, who it is for, what you are building |
| [[People]] | Everyone the agent will hear about, and who they are |
| [[Rules]] | What it must never do without asking you first |
| [[Goals]] | What you are actually trying to achieve, and by when |
| `daily/` | One file per day. What got done, what is still open, what you decided |

The installer fills these in from a short interview. **If it gets something wrong, open the file and fix
it.** Your agent believes the file over its own recollection.

## The one rule that keeps this working

**Every folder gets an index note named after the folder**, like this one. Your agent knows that rule, so
it always knows where to start looking. That convention is doing more work than any piece of software
here.

## Using Obsidian, if you want to

**You do not need it.** These are text files; any editor opens them.

But if you want to browse this visually, [Obsidian](https://obsidian.md) is free, and this folder is
already shaped for it. Point it at this folder as a vault and the `[[double bracket]]` links above become
clickable, you get backlinks showing everything that mentions a note, and search across the lot.

**Nothing changes for your agent either way.** It reads the text.
