"""Spoken tool approval — Lefty asks out loud, Bobby answers out loud.

Voice Line runs headless: no TTY, no prompt surface. Without this, a tool call
needing approval has nowhere to ask and simply fails. The callback turns the
approval into what the rest of the app already is — a conversation.
"""

import asyncio
import os
import re
import time

from claude_agent_sdk import PermissionResultAllow, PermissionResultDeny

import signals

# The memory folder is Lefty's memory, and editing notes in it is explicitly
# exempt from the double-confirm rule. Settings already allow it, but a
# path-specific allow rule does not shadow this callback — only a whole-tool
# entry does, and that would hand over every Edit everywhere. So the exemption
# lives here instead.
#
# Point LEFTY_MEMORY_DIR at your own notes folder if it is not the default.
# Everything OUTSIDE this folder still has to ask out loud before it is written.
VAULT = os.path.realpath(
    os.environ.get("LEFTY_MEMORY_DIR")
    or os.path.expanduser("~/lefty/lefty-in-a-box/memory")
)

_WRITE_TOOLS = ("Edit", "Write", "NotebookEdit")


def _inside_vault(path: str) -> bool:
    """True only if path really resolves inside the vault.

    realpath first: a symlink or a '..' in the path could otherwise point
    somewhere else entirely while still passing a plain string check.
    """
    if not path:
        return False
    resolved = os.path.realpath(path)
    return resolved == VAULT or resolved.startswith(VAULT + os.sep)

# How long to wait for a spoken answer before refusing.
APPROVAL_TIMEOUT_S = 45

# How many times to ask before refusing. Whisper sometimes returns an empty
# string from a clipped or noisy capture, which is a mic artifact rather than
# an answer. One clean re-ask costs a few seconds; a false deny costs the whole
# tool call and makes Bobby restart the request from scratch.
MAX_ASK_ATTEMPTS = 2

# How long to wait for the question to START playing before giving up on the
# handshake and listening anyway.
SPEAK_START_TIMEOUT_S = 3.0

# Let the speaker tail decay before opening the mic, so the last syllable of
# the question doesn't land in the answer.
SETTLE_S = 0.25

# CRITICAL: match on word boundaries, never substrings. "no" lives inside
# "now", so a plain substring test turns "yes do it now" into a refusal.
_YES_RE = re.compile(
    r"\b(yes|yeah|yep|yup|sure|go ahead|do it|approved?|okay|ok|"
    r"affirmative|permission granted|green light)\b"
)
_NO_RE = re.compile(
    r"\b(no|not|nope|don't|do not|deny|denied|stop|cancel|"
    r"negative|hold off|never mind)\b"
)


# The one field per tool that actually tells Bobby what is about to happen.
_SUBJECT_KEYS = ("file_path", "path", "command", "url", "pattern", "notebook_path")


def _describe(tool_name: str, input_data: dict, context) -> str:
    """Plain-language name for what is being asked, best available.

    ToolPermissionContext carries title / display_name / description, but in
    practice they are often empty — the live test came back with all three
    unset. Falling back to the bare tool name would ask "okay to Read?" without
    saying what, which is not enough to consent to. So fall back to the tool
    name plus its subject.
    """
    for attr in ("title", "display_name", "description"):
        value = getattr(context, attr, None)
        if value:
            return str(value)

    for key in _SUBJECT_KEYS:
        subject = (input_data or {}).get(key)
        if subject:
            return f"{tool_name}: {subject}"

    return tool_name


def _audit(line):
    """One line per decision, timestamped, flushed immediately.

    A gate with no record is half a gate: after the fact there is no way to
    answer "what did I approve?". Everything logged here is either the tool's
    own name or the subject Lefty already SAID OUT LOUD, so this adds no
    exposure that the spoken question did not. Contents are never logged --
    the file being read, not what was in it.
    """
    print(f"[consent] {time.strftime('%H:%M:%S')} {line}", flush=True)


def make_voice_consent(mouth, listen):
    """Build a can_use_tool callback that asks Bobby out loud."""

    async def can_use_tool(tool_name, input_data, context):
        # Vault note edits pass silently. Asking out loud for every routine note
        # write turns checkpointing into a call-and-response.
        if tool_name in _WRITE_TOOLS:
            target = (input_data or {}).get("file_path") or (input_data or {}).get(
                "notebook_path"
            )
            if _inside_vault(target):
                # logged too: a silent allow is still an allow
                _audit(f"AUTO  {tool_name}: {target} (inside vault)")
                return PermissionResultAllow()

        what = _describe(tool_name, input_data, context)

        for attempt in range(1, MAX_ASK_ATTEMPTS + 1):
            last_attempt = attempt == MAX_ASK_ATTEMPTS

            if attempt == 1:
                _audit(f"ASK   {what}")
                await mouth.enqueue(
                    f"I need your okay to {what}. "
                    "Hold right control and say yes or no."
                )
            else:
                _audit(f"RETRY {what} <- unclear, asking again")
                await mouth.enqueue(
                    f"I didn't catch that. Hold right control "
                    f"and say yes or no to {what}."
                )

            # CRITICAL: half-duplex. Checking is_speaking right after enqueue
            # can catch it still False, because the playback loop hasn't picked
            # the sentence up yet. Opening the mic there lets Lefty transcribe
            # its own question and answer itself. So wait for speech to START,
            # then END.
            loop = asyncio.get_event_loop()
            deadline = loop.time() + SPEAK_START_TIMEOUT_S
            while not mouth.is_speaking and loop.time() < deadline:
                await asyncio.sleep(0.02)
            while mouth.is_speaking:
                await asyncio.sleep(0.05)
            await asyncio.sleep(SETTLE_S)

            try:
                # CRITICAL: hold-to-talk, never open mic. The open-mic path
                # ended a turn only after 800ms of VAD-silence, and on a hot
                # mic that silence never arrives -- room noise reads as speech.
                # A spoken "yes" was therefore either timed out or handed to
                # whisper buried in noise and transcribed as "". Key down and
                # key up are the boundaries now. This timeout only covers
                # Bobby never pressing the key at all.
                answer = await asyncio.wait_for(
                    listen(), timeout=APPROVAL_TIMEOUT_S
                )
            except asyncio.TimeoutError:
                # No retry here. A silent room stays silent, and a second
                # window would only double the hang before the same refusal.
                _audit(f"DENY  {what} <- no answer in {APPROVAL_TIMEOUT_S}s")
                await mouth.enqueue("I didn't hear an answer, so I'm not doing it.")
                return PermissionResultDeny(
                    message="No answer from Bobby within the approval window."
                )
            except Exception as e:
                # No retry here either: the mic is broken, not misheard.
                _audit(f"DENY  {what} <- mic failed: {type(e).__name__}: {e}")
                return PermissionResultDeny(
                    message=f"Could not capture an answer: {type(e).__name__}: {e}"
                )
            finally:
                signals.set_state("thinking")

            # Whisper emits curly apostrophes; normalize so "don't" still matches.
            said = (answer or "").strip().lower().replace("’", "'")

            # Check NO first: "no, don't do it" also contains "do it".
            if _NO_RE.search(said):
                _audit(f"DENY  {what} <- heard {said!r}")
                return PermissionResultDeny(message=f"Bobby said no: {said!r}")
            if _YES_RE.search(said):
                _audit(f"ALLOW {what} <- heard {said!r}")
                return PermissionResultAllow()

            # CRITICAL: silence and gibberish are not consent. A misheard yes
            # that runs a destructive call is far worse than making Bobby repeat
            # himself. So an unclear answer buys one more ask, never a pass.
            if not last_attempt:
                continue

            _audit(f"DENY  {what} <- unclear, heard {said!r}")
            await mouth.enqueue(
                "I still couldn't tell if that was a yes, so I'm not doing it."
            )
            return PermissionResultDeny(
                message=f"No clear yes or no (heard {said!r})."
            )

        # Unreachable: the last attempt always returns. Kept so that any future
        # edit to the loop still fails closed instead of returning None.
        _audit(f"DENY  {what} <- no decision reached")
        return PermissionResultDeny(message="No approval decision was reached.")

    return can_use_tool
