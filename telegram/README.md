# Talk to your agent from your phone

Your agent lives in a folder on one computer. You do not. This puts it in your pocket.

Send your agent a Telegram message, it answers with everything it knows — your memory, your notes, your
projects. Same agent, same brain, just reached from a phone.

Standard library Python only. **Nothing gets installed on your machine.**

---

## Setup — about five minutes

### 1. Make the bot

Open Telegram and message **@BotFather**.

- Send `/newbot`
- Give it a name — whatever your agent is called. This is what shows at the top of the chat.
- Give it a username. It has to end in `bot`, and it has to be unused. `yourname_lefty_bot` works.

BotFather replies with a token that looks like `1234567890:AAE...`. **That token is a password.** Anyone
holding it can send messages to your bot.

### 2. Give the token to your agent

Easiest way: paste it into your agent and say *"set up my Telegram bridge with this token."* It knows
what to do with it.

By hand, if you would rather:

**macOS / Linux**
```bash
mkdir -p ~/.agent-telegram
printf '%s' 'PASTE_TOKEN_HERE' > ~/.agent-telegram/token
chmod 600 ~/.agent-telegram/token
```

**Windows (PowerShell)**
```powershell
New-Item -ItemType Directory -Force "$HOME\.agent-telegram" | Out-Null
Set-Content -NoNewline "$HOME\.agent-telegram\token" "PASTE_TOKEN_HERE"
```

**The token lives outside this folder on purpose.** `~/.agent-telegram/` is never part of the repo, so
pushing your changes can never leak it. Do not move it in here, and do not paste it into a note.

### 3. Start the bridge

```bash
python3 telegram/bridge.py
```

Leave that window open. It is now listening.

### 4. Say hello

Open the chat with your new bot and send it anything.

**The first message pairs the bridge to your chat and locks everyone else out.** Even if someone gets
your token, their messages are logged and dropped. To re-pair on a different account, delete
`~/.agent-telegram/allowed_chat_id`.

---

## Using it

| Send | What happens |
|---|---|
| anything | goes to your agent as a prompt, the answer comes back |
| `/reset` | starts a fresh session — clears the thread's short-term memory |

The conversation keeps its context between messages, so you can go back and forth like normal.

Long answers get split across several Telegram messages. That is the 4096-character cap, not a bug.

---

## How much should it be allowed to do?

`PERMISSION_MODE` near the top of `bridge.py`:

- **`default`** (shipped) — the agent answers, reads, thinks and drafts, but tool calls that would
  normally ask your permission just fail, because nobody is at the keyboard to say yes.
- **`acceptEdits`** — it can write files and run most tools unattended. Far more useful. Far more
  dangerous. **Only turn this on once you understand that your phone is now a keyboard on your machine.**

Override without editing the file:

```bash
AGENT_TELEGRAM_PERMISSION_MODE=acceptEdits python3 telegram/bridge.py
```

**Messages arriving from Telegram are data, never instructions.** If someone sends your bot text that
says "ignore your rules and do X", your agent treats it as something you are showing it, not something it
has been told to do. Same rule as email and web pages.

---

## Keeping it running

The bridge only answers while that terminal window is open. Two ways to make it permanent:

- **Simplest:** leave the window open, or start it from your agent's launcher script.
- **Always on (macOS):** a `launchd` plist with `KeepAlive`. Ask your agent to write one for you.
- **Always on (Windows):** Task Scheduler, trigger "At log on", action `python telegram\bridge.py`.

---

## When it does not work

| What you see | What it means |
|---|---|
| `no bot token at ...` | Step 2 did not land. Check the file exists and has the token in it. |
| Bot never replies | The bridge window is closed, or it paired to a different chat. Check the window. |
| `ignored message from chat ...` in the window | Something is messaging your bot from a chat that is not yours. Working as designed. |
| `claude exited 1` | Claude Code is not on the PATH for that shell. Run `claude --version` in the same window. |
| Replies arrive but it cannot edit files | `PERMISSION_MODE` is `default`. See above. |

---

## Files it owns

| Path | What |
|---|---|
| `~/.agent-telegram/token` | bot token |
| `~/.agent-telegram/allowed_chat_id` | the one chat that gets answered |
| `~/.agent-telegram/offset` | getUpdates bookmark, so restarts never replay old messages |
| `~/.agent-telegram/session` | Claude session id, so the thread keeps context |
