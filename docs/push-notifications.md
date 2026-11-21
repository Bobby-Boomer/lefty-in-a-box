# Push notifications — getting your agent to reach your phone

## The symptom you would notice

**You ask your agent to text you when something finishes. You drive off. Nothing ever arrives.**

Or worse, the quiet version: reminders you set up weeks ago simply stopped landing, and nothing
anywhere said so. The scheduled job still shows as healthy. The log says the message was sent.

That is the failure this page exists to prevent, and it is a real one — it happened on the machine
this kit was built on, and it went unnoticed for an unknown number of days.

## Why it happens, and why it hides

Two bugs stack up, and the second one hides the first.

1. **A revoked Telegram bot token still looks fine on disk.** Telegram answers `401 Unauthorized`,
   but the token file is still there, still the right length, still the right shape. Any check of the
   form "does the token file exist and is it non-empty" passes with flying colours while every single
   message is thrown away.

2. **A long-running poller reports the wrong error.** The bridge process logged
   `poll failed: The read operation timed out` over and over. That reads like a flaky network. It is
   actually an auth failure, and it completely masks the real cause — so the process shows as alive
   in the service list and is, in fact, mute.

Net effect: **a channel that is dead but reports success.** The worst kind, because you only find out
when something important does not reach you.

## The rule this implements

**A dead channel must say so.** Never time out quietly, never swallow a 401, and never exit 0 when
nothing was actually delivered.

`voice-line/notify.py` enforces it:

- It calls Telegram's `getMe` to **verify the channel authenticates before trying to send.**
- When a token is unauthorized it says **which channel died and what to do about it**, by name.
- **Exit codes carry the truth:** `0` delivered to the phone, `3` no channel could authenticate,
  `4` fell back to a desktop notification and the phone was *not* reached. A caller that checks the
  exit code cannot be fooled.

## Setting it up

Two channels are supported, tried in that order. The first one that **authenticates** wins.

### 1. The Claude Telegram plugin (recommended)

If you use the official Telegram plugin, you already have a working bot and nothing more is needed.
`notify.py` reads:

```
$CLAUDE_CONFIG_DIR/channels/telegram/.env          # TELEGRAM_BOT_TOKEN
$CLAUDE_CONFIG_DIR/channels/telegram/access.json   # allowFrom -> your chat id
```

`CLAUDE_CONFIG_DIR` defaults to `~/.claude`. If `access.json` has no `allowFrom` entry, message your
bot once to pair it — `notify.py` will tell you that is what is missing rather than failing blankly.

### 2. A standalone bot

Make a bot with [@BotFather](https://t.me/botfather), then:

```bash
mkdir -p ~/.agent-telegram
printf '%s' '<your-token>' > ~/.agent-telegram/token
chmod 600 ~/.agent-telegram/token
export AGENT_TELEGRAM_CHAT_ID='<your-chat-id>'
```

Override the token path with `AGENT_TELEGRAM_TOKEN_FILE` if you keep it elsewhere.

**Never write a token into a note, a doc, or this repo.**

## Using it

```bash
# test every channel, send nothing
voice-line/notify.py --check

# plain message
voice-line/notify.py "the overnight job finished"

# message plus a tap-to-talk link into the phone voice line
voice-line/notify.py --phone-link "I read the notes, tap to talk it through"
```

### The `--phone-link` flag is the good part

The phone voice line (see [phone-line.md](phone-line.md)) is **inbound only** — it answers when you
open the page, and it cannot dial out. That is correct design, but it means the voice line alone is
not a notification channel.

`--phone-link` closes the loop. It runs `phone/url.sh`, grabs the current reachable URL, and appends
it to the message. **You tap the notification and land in a live voice conversation with your agent.**
The link carries an access key, so it is sent to you and never logged or written to a file.

## Wiring it into your own scripts

Call it and **check the exit code**. That is the whole discipline:

```bash
if ! notify.py "$MESSAGE"; then
  log "NOT DELIVERED - see stderr above for which channel died"
fi
```

The reminder engine in `bin/` does exactly this. Its previous version posted straight to the Telegram
API and logged a success unconditionally, which is how the outage stayed invisible.

## Verifying it actually works

Do not trust a clean `--check`. Prove both directions:

```bash
# 1. the happy path — a message should arrive on your phone
voice-line/notify.py "test, no reply needed"; echo "exit=$?"     # expect 0

# 2. the failure path — point it at a config that cannot work
CLAUDE_CONFIG_DIR=/tmp/nope AGENT_TELEGRAM_CHAT_ID=1 \
  voice-line/notify.py --check; echo "exit=$?"                   # expect 3, and a named reason
```

**Test number 2 is the one that matters.** A notification system that works is easy; one that tells
you when it has stopped working is the thing you actually needed.

## What this does not do

- **It is not browser web push.** Real web push to the phone page needs a publicly trusted
  certificate, and the phone line ships with a self-signed one for LAN and tunnel use. Telegram plus
  a deep link gets you the same outcome today without a certificate authority in the loop.
- **It does not retry on a schedule.** One attempt per channel, then an honest exit code. Retrying is
  the caller's decision, because only the caller knows if the message still matters.
