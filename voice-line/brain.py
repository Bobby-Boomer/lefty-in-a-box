"""Warm Claude Agent SDK session with streaming and sentence chunking."""

import asyncio
import json
import re
import os
import time
from pathlib import Path
from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
)

# Quit phrases that end the session
QUIT_PHRASES = {"goodbye", "end voice mode", "hang up"}

# Sentence-ending punctuation
_SENTENCE_END = re.compile(r'(?<=[.!?])\s+')

SPOKEN_DISCIPLINE = """
IMPORTANT — you are in VOICE MODE. Your replies will be spoken aloud through TTS.
Rules for spoken output:
- Write short, conversational sentences. Write for the ear, not the eye.
- NO markdown formatting, NO code blocks, NO bullet lists, NO numbered lists.
- NO asterisks, NO bold, NO headers. Plain spoken English only.
- Punctuation matters — TTS performs it. Dull flat text = dull flat audio.
- After your first sentence, group sentences in pairs (two-sentence breaths) since lone short sentences sound flat.
- If you need to show code or structured data, say "I'll put that in a file for you" and use a tool instead.
- Keep responses concise. This is a conversation, not an essay.
- Never read URLs, file paths, or technical identifiers aloud character by character. Summarize them.
"""

# Working directory — defaults to the Lefty project for Bobby's vault context
DEFAULT_CWD = os.path.expanduser("~/documents/Lefty")

# CRITICAL: query() is one-shot — without resume, every turn is a brand-new
# session and the conversation cannot remember the sentence before it. We hold
# the session id and thread it through every turn.
SESSION_FILE = Path(__file__).with_name(".voice_session")

# A relaunch inside this window rejoins the same conversation. Past it, boot
# fresh and let the vault carry the history — the vault is the memory, not the
# transcript, and dragging a week-old context blob into every boot is worse.
SESSION_MAX_AGE_S = 12 * 60 * 60

# The SDK frames the CLI's stdout as NDJSON and refuses any single line bigger
# than this. The default is 1MB, which one fat tool result (a long file read, a
# wide grep) blows straight through — the transport then raises
# "Failed to decode JSON message ... exceeded maximum buffer size" and the whole
# voice line falls over. Give it real headroom.
MAX_BUFFER_SIZE = int(os.environ.get("VOICE_MAX_BUFFER_SIZE", 64 * 1024 * 1024))

# Keep the Claude Code system prompt (tools, file access) and append voice rules.
SYSTEM_PROMPT = {
    "type": "preset",
    "preset": "claude_code",
    "append": SPOKEN_DISCIPLINE,
}


class Brain:
    def __init__(self, cwd: str = None, can_use_tool=None):
        self._cwd = cwd or DEFAULT_CWD
        self._warmed = False
        self._can_use_tool = can_use_tool
        self._session_id = self._load_session()

    # ── Session continuity ──────────────────────────────────────────────────

    def _load_session(self) -> str | None:
        """Stored session id, or None if absent, unreadable, or too old."""
        try:
            data = json.loads(SESSION_FILE.read_text())
        except (OSError, ValueError):
            return None
        session_id = data.get("session_id")
        saved_at = data.get("saved_at", 0)
        if not session_id or (time.time() - saved_at) > SESSION_MAX_AGE_S:
            return None
        return session_id

    def _save_session(self, session_id: str) -> None:
        """Record the live session id. A write failure must not kill the turn."""
        if not session_id:
            return
        self._session_id = session_id
        try:
            SESSION_FILE.write_text(
                json.dumps({"session_id": session_id, "saved_at": time.time()})
            )
        except OSError:
            pass

    def _clear_session(self) -> None:
        self._session_id = None
        try:
            SESSION_FILE.unlink(missing_ok=True)
        except OSError:
            pass

    def _options(self, max_turns: int = None) -> ClaudeAgentOptions:
        return ClaudeAgentOptions(
            cwd=self._cwd,
            system_prompt=SYSTEM_PROMPT,
            resume=self._session_id,
            max_turns=max_turns,
            can_use_tool=self._can_use_tool,
            max_buffer_size=MAX_BUFFER_SIZE,
        )

    @staticmethod
    async def _stream_prompt(text: str, done: asyncio.Event):
        """Wrap one turn as an AsyncIterable, held open until the turn ends.

        CRITICAL (two separate traps, both learned the hard way):

        1. The SDK refuses a can_use_tool callback when the prompt is a plain
           string — approvals travel over the control protocol, which only
           exists in streaming mode.

        2. Yielding once and returning closes the input stream immediately, and
           the approval round trip rides that same connection. A tool asking for
           permission after it closes gets "permission request aborted before it
           could even be asked." So the generator waits on `done`, which the
           caller sets once the turn's ResultMessage lands.
        """
        yield {
            "type": "user",
            "message": {"role": "user", "content": text},
            "parent_tool_use_id": None,
            "session_id": "default",
        }
        await done.wait()

    async def warmup(self, on_sentence=None):
        """Fire a warmup query to prime the prompt cache.
        Speak the greeting so the user hears something while cache loads.
        """
        greeting = "Let's get started."
        if on_sentence:
            await on_sentence(greeting)

        # Warm the session with a no-op query. This also anchors the session:
        # whatever id comes back is what every later turn resumes into.
        done = asyncio.Event()
        try:
            async for msg in query(
                prompt=self._stream_prompt("Say exactly: Ready when you are.", done),
                options=self._options(max_turns=1),
            ):
                if isinstance(msg, ResultMessage):
                    self._save_session(msg.session_id)
                    done.set()
        finally:
            # Release the prompt generator even if the turn raised, or it
            # would sit waiting on an event nobody is left to set.
            done.set()
        self._warmed = True

    async def turn(self, user_text: str, on_sentence=None) -> str:
        """Send user text to Claude, stream response, chunk into sentences.

        on_sentence(text) is called for each complete sentence.
        Returns the full response text.
        """
        spoke = []
        try:
            return await self._run_turn(user_text, on_sentence, spoke)
        except Exception:
            # CRITICAL: only safe to retry before anything reached the speaker.
            # Retrying mid-reply would say the first half of it twice.
            if self._session_id is None or spoke:
                raise
            # The stored session was rejected — expired or pruned. Drop it and
            # take the turn fresh rather than losing what Bobby just said.
            self._clear_session()
            return await self._run_turn(user_text, on_sentence, spoke)

    async def _run_turn(self, user_text: str, on_sentence, spoke: list) -> str:
        """One streamed exchange. Appends to `spoke` once audio has gone out."""
        full_response = []
        buffer = ""
        done = asyncio.Event()

        try:
            async for msg in query(
                prompt=self._stream_prompt(user_text, done),
                options=self._options(),
            ):
                if isinstance(msg, ResultMessage):
                    self._save_session(msg.session_id)
                    done.set()
                if isinstance(msg, AssistantMessage):
                    for block in msg.content:
                        if hasattr(block, "text") and block.text:
                            buffer += block.text
                            full_response.append(block.text)

                            # Chunk into sentences
                            while True:
                                match = _SENTENCE_END.search(buffer)
                                if not match:
                                    break
                                sentence = buffer[: match.start() + 1].strip()
                                buffer = buffer[match.end():]
                                if sentence and on_sentence:
                                    spoke.append(True)
                                    await on_sentence(sentence)
        finally:
            # Release the prompt generator even if the turn raised, or it
            # would sit waiting on an event nobody is left to set.
            done.set()

        # CRITICAL: flush remaining buffer when content block stops
        # Pre-tool filler like "On it, checking now" would sit silent otherwise
        if buffer.strip() and on_sentence:
            spoke.append(True)
            await on_sentence(buffer.strip())

        return "".join(full_response)

    def is_quit(self, text: str) -> bool:
        return text.strip().lower() in QUIT_PHRASES
