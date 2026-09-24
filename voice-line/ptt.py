"""Global hold-to-talk key listener via pynput.

CRITICAL: OS fires key-repeat on_press events continuously while held.
We filter with a held-state flag so repeats don't become fresh presses.
"""

import asyncio
from pynput import keyboard

# Default PTT key — right command on mac
PTT_KEY = keyboard.Key.ctrl_r

# Timing constants
RELEASE_TAIL_S = 0.18   # keep mic open this long after release


class PushToTalk:
    def __init__(self, loop: asyncio.AbstractEventLoop):
        self._loop = loop
        self._held = False
        self._on_press_cb = None
        self._on_release_cb = None
        self._on_interrupt_cb = None
        self._listener = None

    def set_callbacks(self, on_press, on_release, on_interrupt):
        """on_press: mic opens. on_release: mic closes. on_interrupt: cancel playback."""
        self._on_press_cb = on_press
        self._on_release_cb = on_release
        self._on_interrupt_cb = on_interrupt

    def start(self):
        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        )
        self._listener.daemon = True
        self._listener.start()

    def stop(self):
        if self._listener:
            self._listener.stop()

    @property
    def is_held(self) -> bool:
        """True while the key is physically down.

        Needed because an interrupt consumes a press, and by the time the turn
        has finished cancelling, the user may already have let go. Opening the
        mic then would wait for a release that already happened, and Bobby
        would have to press several more times to get anywhere.
        """
        return self._held

    def _on_press(self, key):
        if key != PTT_KEY:
            return
        # CRITICAL: filter key-repeat — only act on the first press
        if self._held:
            return
        self._held = True

        # If mouth is speaking, this is an interrupt
        if self._on_interrupt_cb:
            self._loop.call_soon_threadsafe(self._on_interrupt_cb)

        if self._on_press_cb:
            self._loop.call_soon_threadsafe(self._on_press_cb)

    def _on_release(self, key):
        if key != PTT_KEY:
            return
        if not self._held:
            return
        self._held = False

        # CRITICAL: always fire release, even for a quick tap. The
        # caller is blocked waiting for it; skipping leaves the mic open forever.
        # Short taps are discarded downstream by the MIN_AUDIO_BYTES guard.
        if self._on_release_cb:
            self._loop.call_soon_threadsafe(
                lambda: self._loop.create_task(self._delayed_release())
            )

    async def _delayed_release(self):
        await asyncio.sleep(RELEASE_TAIL_S)
        # If user pressed again during tail, don't release
        if not self._held and self._on_release_cb:
            self._on_release_cb()
