#!/usr/bin/env python3
"""
Telegram bridge — talk to your agent from your phone.

Long-polls a Telegram bot, hands each message to Claude Code running in this
folder, and sends the reply back. Same agent, same memory, same vault — reached
from a phone instead of the terminal.

Standard library only. Nothing to install. Works the same on macOS and Windows.

Secrets live OUTSIDE this repo, in ~/.agent-telegram/, so a git push can never
leak them:
    token              the BotFather bot token          (chmod 600 on macOS/Linux)
    allowed_chat_id    the one chat allowed to talk     (written on first pairing)
    offset             getUpdates bookmark
    session            the Claude session id, so the thread keeps its memory

Run:  python3 telegram/bridge.py          (long-poll forever)
      python3 telegram/bridge.py --once   (handle one batch and exit, for testing)

Setup, start to finish: telegram/README.md
"""

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

CONF = Path.home() / ".agent-telegram"
WORKDIR = Path(__file__).resolve().parent.parent     # the agent folder, one level up
CLAUDE = shutil.which("claude") or "claude"

# How much the agent is allowed to do with nobody at the keyboard.
#
#   "default"     — asks permission, so tool calls that need it simply fail in headless mode.
#                   Safe. Good for asking questions, reading memory, drafting.
#   "acceptEdits" — file edits and most tools run unattended. Much more useful,
#                   much more dangerous.
#
# Anything reachable from Telegram is only as safe as the bot token. Start at "default".
PERMISSION_MODE = os.environ.get("AGENT_TELEGRAM_PERMISSION_MODE", "default")

TG_LIMIT = 4000          # Telegram caps a message at 4096 chars; leave headroom
POLL_TIMEOUT = 50        # seconds held open by getUpdates long polling
CLAUDE_TIMEOUT = 600     # seconds before a single reply is abandoned


def conf_read(name, default=None):
    p = CONF / name
    return p.read_text().strip() if p.exists() else default


def conf_write(name, value):
    CONF.mkdir(parents=True, exist_ok=True)
    p = CONF / name
    p.write_text(str(value))
    try:
        p.chmod(0o600)
    except OSError:
        pass                                   # Windows does not do POSIX modes


def api(method, **params):
    token = conf_read("token")
    if not token:
        raise SystemExit(f"no bot token at {CONF / 'token'} — see telegram/README.md")
    url = f"https://api.telegram.org/bot{token}/{method}"
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req, timeout=POLL_TIMEOUT + 15) as r:
        return json.loads(r.read().decode())


def send(chat_id, text):
    for i in range(0, len(text), TG_LIMIT):
        api("sendMessage", chat_id=chat_id, text=text[i:i + TG_LIMIT])


def ask_agent(prompt):
    """Run one turn through Claude Code, keeping the same session across messages."""
    base = [CLAUDE, "-p", prompt, "--output-format", "json",
            "--permission-mode", PERMISSION_MODE]
    sid = conf_read("session")
    cmd = base + (["--resume", sid] if sid else [])

    r = subprocess.run(cmd, cwd=str(WORKDIR), capture_output=True,
                       text=True, timeout=CLAUDE_TIMEOUT)

    if r.returncode != 0 and sid:
        # A stale session id is the usual cause. Drop it and take the turn fresh.
        (CONF / "session").unlink(missing_ok=True)
        r = subprocess.run(base, cwd=str(WORKDIR), capture_output=True,
                           text=True, timeout=CLAUDE_TIMEOUT)

    if r.returncode != 0:
        return f"[bridge] claude exited {r.returncode}: {(r.stderr or '').strip()[:500]}"

    try:
        out = json.loads(r.stdout)
    except json.JSONDecodeError:
        return (r.stdout or "").strip()[:TG_LIMIT] or "[bridge] empty reply"

    if out.get("session_id"):
        conf_write("session", out["session_id"])
    return out.get("result") or "[bridge] empty reply"


def handle(msg):
    chat_id = str(msg.get("chat", {}).get("id", ""))
    text = (msg.get("text") or "").strip()
    if not text:
        return

    allowed = conf_read("allowed_chat_id")
    if not allowed:
        # First contact pairs the bridge to that chat and nobody else.
        conf_write("allowed_chat_id", chat_id)
        allowed = chat_id
        send(chat_id, f"Paired. This chat ({chat_id}) is now the only one I answer.")
    if chat_id != allowed:
        print(f"ignored message from chat {chat_id}", flush=True)
        return

    if text == "/reset":
        (CONF / "session").unlink(missing_ok=True)
        send(chat_id, "Fresh session.")
        return

    print(f"-> {text[:80]}", flush=True)
    api("sendChatAction", chat_id=chat_id, action="typing")
    try:
        reply = ask_agent(text)
    except subprocess.TimeoutExpired:
        reply = "[bridge] that one took too long and got cut off. Try a smaller ask."
    send(chat_id, reply)
    print(f"<- {reply[:80]}", flush=True)


def main():
    once = "--once" in sys.argv
    offset = int(conf_read("offset", "0"))
    print(f"bridge up, offset {offset}, workdir {WORKDIR}", flush=True)

    while True:
        try:
            res = api("getUpdates", offset=offset, timeout=POLL_TIMEOUT)
        except Exception as e:
            print(f"poll failed: {e}", flush=True)
            time.sleep(5)
            continue

        for upd in res.get("result", []):
            offset = upd["update_id"] + 1
            conf_write("offset", offset)
            msg = upd.get("message") or upd.get("edited_message")
            if msg:
                try:
                    handle(msg)
                except Exception as e:
                    print(f"handler failed: {e}", flush=True)

        if once:
            return


if __name__ == "__main__":
    main()
