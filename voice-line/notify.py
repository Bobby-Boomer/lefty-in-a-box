#!/usr/bin/env python3
"""
notify.py — push a message from the agent to its owner's phone.

WHY THIS EXISTS (the failure it was born from, 2026-11-20/21):
    The only push channel off this machine was a Telegram bot token in
    ~/.agent-telegram/token. That token was revoked at some unknown point and
    started returning 401 Unauthorized. Nothing noticed, because:

      * remind.sh only checked that the token FILE EXISTED, never that it
        WORKED. A file that is present but unauthorized sailed straight past
        the guard and every reminder since then went nowhere.
      * the long-running bridge logged "poll failed: read operation timed out",
        which reads like a flaky network and completely masks an auth failure.
        The job looked healthy in `launchctl list` and was silently mute.

    So the rule this file enforces: A DEAD CHANNEL MUST SAY SO. Never time out
    quietly, never swallow a 401, and never exit 0 when nothing was delivered.

CHANNELS, tried in order. First one that AUTHENTICATES wins:
    1. The official Claude Telegram plugin channel
         $CLAUDE_CONFIG_DIR/channels/telegram/.env      (TELEGRAM_BOT_TOKEN)
         $CLAUDE_CONFIG_DIR/channels/telegram/access.json (allowFrom -> chat id)
    2. A standalone bot
         $AGENT_TELEGRAM_TOKEN_FILE  (default ~/.agent-telegram/token)
         $AGENT_TELEGRAM_CHAT_ID
    3. Local desktop notification — a LAST RESORT that only helps if the owner
       is sitting at the machine. Counted as "not delivered to the phone".

USAGE
    notify.py "the brief is done"
    notify.py --phone-link "I read the notes, tap to talk"   # deep-links the voice line
    notify.py --check                                        # test channels, send nothing

EXIT CODES
    0  delivered to the phone
    3  no channel could authenticate (details on stderr)
    4  delivered only to the local desktop, NOT to the phone
"""

import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.abspath(__file__))
TIMEOUT = 15
TOKEN_RE = re.compile(r"[0-9]{6,}:[A-Za-z0-9_-]{30,}")


def log(msg):
    print(msg, file=sys.stderr)


def claude_config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")


def _tg(token, method, params=None):
    """One Telegram API call. Returns (ok, payload_or_error_string)."""
    url = f"https://api.telegram.org/bot{token}/{method}"
    data = urllib.parse.urlencode(params).encode() if params else None
    try:
        with urllib.request.urlopen(url, data=data, timeout=TIMEOUT) as r:
            body = json.load(r)
    except urllib.error.HTTPError as e:
        # A 401 arrives as an HTTPError. Read the body so the REASON survives
        # instead of being reported as a generic failure.
        try:
            body = json.load(e)
        except Exception:
            return False, f"HTTP {e.code}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"
    if not body.get("ok"):
        return False, body.get("description", "unknown error")
    return True, body.get("result", {})


def read_env_value(path, key):
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line.startswith(f"{key}="):
                    return line.split("=", 1)[1].strip().strip("'\"")
    except OSError:
        return None
    return None


def candidates():
    """Yield (label, token, chat_id) for every configured channel."""
    # 1. the official plugin channel
    ch = os.path.join(claude_config_dir(), "channels", "telegram")
    tok = read_env_value(os.path.join(ch, ".env"), "TELEGRAM_BOT_TOKEN")
    chat = None
    try:
        with open(os.path.join(ch, "access.json")) as f:
            allow = json.load(f).get("allowFrom") or []
            chat = str(allow[0]) if allow else None
    except OSError:
        pass
    if tok and chat:
        yield "claude telegram plugin", tok, chat
    elif tok and not chat:
        log("note: plugin bot token present but access.json has no allowFrom "
            "chat id — pair the bot by messaging it once, then retry.")

    # 2. a standalone bot
    tf = os.environ.get("AGENT_TELEGRAM_TOKEN_FILE",
                        os.path.join(HOME, ".agent-telegram", "token"))
    chat2 = os.environ.get("AGENT_TELEGRAM_CHAT_ID")
    if os.path.isfile(tf) and os.path.getsize(tf) > 0:
        with open(tf) as f:
            tok2 = f.read().strip()
        tok2 = (TOKEN_RE.search(tok2) or [None])[0] if not TOKEN_RE.fullmatch(tok2) else tok2
        if isinstance(tok2, str) and tok2 and chat2:
            yield "standalone bot", tok2, chat2
        elif isinstance(tok2, str) and tok2 and not chat2:
            log(f"note: {tf} holds a token but AGENT_TELEGRAM_CHAT_ID is unset, "
                "so there is nobody to send it to.")


def phone_link():
    """The live phone voice-line URL. Carries an access key, so it is never logged."""
    script = os.path.join(HERE, "phone", "url.sh")
    if not os.access(script, os.X_OK):
        return None
    try:
        out = subprocess.run([script], capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    for line in out.stdout.splitlines():
        line = line.strip()
        if line.startswith("https://"):
            return line
    return None


def desktop(msg):
    try:
        subprocess.run(
            ["/usr/bin/osascript", "-e",
             'display notification {} with title "Agent"'.format(json.dumps(msg[:200]))],
            capture_output=True, timeout=10)
        return True
    except Exception:
        return False


def main():
    args = sys.argv[1:]
    check_only = "--check" in args
    want_link = "--phone-link" in args
    body = " ".join(a for a in args if not a.startswith("--")).strip()

    if not body and not check_only:
        log("usage: notify.py [--phone-link] \"message\"   |   notify.py --check")
        return 2

    live = []
    for label, token, chat in candidates():
        ok, res = _tg(token, "getMe")
        if not ok:
            # THE WHOLE POINT: say exactly what is wrong, out loud.
            log(f"channel DEAD  [{label}]: {res}")
            if "unauthorized" in str(res).lower():
                log("              -> the token is revoked or regenerated. "
                    "Get a fresh one from BotFather and rewrite the token file.")
            continue
        log(f"channel live  [{label}]: @{res.get('username')}")
        live.append((label, token, chat))

    if check_only:
        if not live:
            log("RESULT: no working push channel. The phone cannot be reached.")
            return 3
        log(f"RESULT: {len(live)} working channel(s).")
        return 0

    if want_link:
        link = phone_link()
        if link:
            body = f"{body}\n\nTalk to me: {link}"
        else:
            log("note: could not build the phone link; sending the message without it.")

    for label, token, chat in live:
        ok, res = _tg(token, "sendMessage",
                      {"chat_id": chat, "text": body, "disable_web_page_preview": "true"})
        if ok:
            log(f"delivered via {label} (message {res.get('message_id')})")
            return 0
        log(f"send FAILED  [{label}]: {res}")

    # Nothing reached the phone. Make noise locally and FAIL, so a caller that
    # checks the exit code learns the truth rather than assuming success.
    if desktop(body):
        log("FELL BACK to a desktop notification — this only helps at the machine.")
        return 4
    log("NOT DELIVERED anywhere.")
    return 3


if __name__ == "__main__":
    sys.exit(main())
