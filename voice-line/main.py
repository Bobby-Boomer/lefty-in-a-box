"""Voice Line — hold-to-talk voice conversation with Claude.

Entry point, turn loop, PTT wiring, typed input with raw terminal line editor.
"""

import argparse
import asyncio
import io
import os
import sys
import termios
import tty

import consent
import signals
import ears as ears_mod
import traceback
from datetime import datetime
from pathlib import Path
from ptt import PushToTalk
from ears import Ears
from brain import Brain
from mouth import Mouth
import ducking

# ── Crash log ───────────────────────────────────────────────────────────────
# The launcher does not capture main.py's output, so when the app dies the
# traceback scrolls past in the terminal and is gone. Every unexpected exit
# now lands here with a full traceback, which is the only way to fix a crash
# we cannot reproduce on demand.

CRASH_LOG = Path(__file__).with_name("crash.log")


def log_crash(tag: str, exc: BaseException) -> None:
    """Append a timestamped traceback. Never raise from inside a crash handler."""
    try:
        with CRASH_LOG.open("a") as f:
            f.write(f"\n{'=' * 70}\n{datetime.now().isoformat()}  [{tag}]  "
                    f"{type(exc).__name__}: {exc}\n")
            traceback.print_exception(type(exc), exc, exc.__traceback__, file=f)
            # ExceptionGroup hides the real cause in .exceptions, not __cause__.
            for sub in getattr(exc, "exceptions", ()) or ():
                f.write(f"\n--- sub-exception: {type(sub).__name__}: {sub}\n")
                traceback.print_exception(type(sub), sub, sub.__traceback__, file=f)
    except Exception:
        pass


# ── Raw terminal line editor ────────────────────────────────────────────────
# Take terminal raw (cbreak, kernel echo off, restore on exit).
# Run our own tiny line editor: assemble bracketed pastes invisibly into ONE
# message, scrub gutter glyphs and hard wraps, echo long paste as char count.

_original_termios = None

# Bracketed paste sequences
_PASTE_START = b"\x1b[200~"
_PASTE_END = b"\x1b[201~"


def _enter_raw() -> bool:
    """Put the terminal in cbreak mode. False if stdin isn't a real terminal.

    Piped/background stdin has no termios state; the raw line editor is simply
    unavailable there (voice still works).
    """
    global _original_termios
    if not sys.stdin.isatty():
        return False
    try:
        fd = sys.stdin.fileno()
        _original_termios = termios.tcgetattr(fd)
        tty.setcbreak(fd)
        return True
    except (termios.error, ValueError, io.UnsupportedOperation) as e:
        print(f"[warn] Raw terminal unavailable ({e}) — typed input disabled.")
        return False


def _restore_terminal():
    if _original_termios:
        fd = sys.stdin.fileno()
        termios.tcsetattr(fd, termios.TCSADRAIN, _original_termios)


async def _read_line_raw() -> str:
    """Read a line from stdin with raw terminal handling.

    Handles bracketed paste: assembles into one message, scrubs gutter glyphs
    and hard wraps, echoes long paste as char count instead of text.
    """
    loop = asyncio.get_event_loop()
    buf = []
    in_paste = False
    paste_buf = []
    raw_input = b""

    while True:
        # Read one byte at a time
        byte = await loop.run_in_executor(None, lambda: os.read(sys.stdin.fileno(), 1))
        if not byte:
            continue

        raw_input += byte

        # Check for bracketed paste start
        if raw_input.endswith(_PASTE_START):
            in_paste = True
            paste_buf = []
            raw_input = b""
            continue

        # Check for bracketed paste end
        if in_paste and raw_input.endswith(_PASTE_END):
            in_paste = False
            raw_input = b""
            # Process paste: scrub gutter glyphs, hard wraps
            pasted = "".join(paste_buf)
            pasted = _scrub_paste(pasted)
            if len(pasted) > 80:
                sys.stdout.write(f"[pasted {len(pasted)} chars]")
            else:
                sys.stdout.write(pasted)
            sys.stdout.flush()
            buf.append(pasted)
            continue

        if in_paste:
            try:
                paste_buf.append(byte.decode("utf-8", errors="replace"))
            except Exception:
                pass
            continue

        # Normal input
        ch = byte[0]

        if ch in (10, 13):  # Enter
            sys.stdout.write("\n")
            sys.stdout.flush()
            return "".join(buf)
        elif ch == 127 or ch == 8:  # Backspace
            if buf:
                buf.pop()
                sys.stdout.write("\b \b")
                sys.stdout.flush()
        elif ch == 3:  # Ctrl-C
            raise KeyboardInterrupt
        elif ch == 4:  # Ctrl-D
            raise EOFError
        elif ch >= 32:  # Printable
            char = chr(ch)
            buf.append(char)
            sys.stdout.write(char)
            sys.stdout.flush()

        raw_input = b""


def _scrub_paste(text: str) -> str:
    """Clean up pasted text: remove gutter glyphs, normalize whitespace."""
    import re
    # Remove common gutter characters (line numbers, prompts, etc.)
    lines = text.split("\n")
    cleaned = []
    for line in lines:
        # Strip leading line numbers like "  1 │ " or "  42: "
        line = re.sub(r"^\s*\d+\s*[│|:]\s?", "", line)
        # Strip leading prompt characters
        line = re.sub(r"^[>$#%]\s?", "", line)
        cleaned.append(line)
    # Join with spaces (collapse hard wraps) unless there are blank lines
    result = "\n".join(cleaned)
    return result.strip()


# ── Turn handler ────────────────────────────────────────────────────────────

async def run_turn_interruptible(text, brain, mouth, ptt_event, get_action) -> tuple[bool, bool]:
    """Run one turn, but let a push-to-talk press cut it short.

    Returns (quit, interrupted).

    THE BUG THIS FIXES. The main loop used to `await handle_turn(...)` inline.
    While that was running -- and a turn can run for minutes on tool calls --
    nothing was awaiting `ptt_event`. The key listener still fired and still set
    the event, but the next pass of the loop began with `ptt_event.clear()`,
    which wiped it. So holding the key during a turn did nothing at all, and the
    press was silently discarded. Bobby: "I'm holding the control button and I
    can't speak to you."

    Now the turn and the key race each other. If Bobby presses, he wins: the
    turn is cancelled, the mouth shuts up, and the mic opens.
    """
    signals.set_busy(True)
    try:
        ptt_event.clear()
        turn_task = asyncio.ensure_future(handle_turn(text, brain, mouth))
        press_task = asyncio.ensure_future(ptt_event.wait())

        done, _ = await asyncio.wait(
            {turn_task, press_task}, return_when=asyncio.FIRST_COMPLETED
        )

        if press_task in done and get_action() == "pressed":
            mouth.interrupt()
            turn_task.cancel()
            try:
                await turn_task
            except (KeyboardInterrupt, SystemExit):
                raise
            except BaseException:
                pass  # a cancelled turn is the point, not an error
            sys.stdout.write("\r[interrupted -- go ahead]      \n")
            sys.stdout.flush()
            return False, True

        press_task.cancel()
        quit = False
        if not turn_task.cancelled():
            try:
                quit = turn_task.result()
            except (KeyboardInterrupt, SystemExit):
                raise
            except BaseException:
                quit = False
        return quit, False
    finally:
        signals.set_busy(False)


async def handle_turn(text: str, brain: Brain, mouth: Mouth) -> bool:
    """Process one turn: send to brain, speak response. Returns True to quit."""
    if not text:
        return False

    if brain.is_quit(text):
        await mouth.enqueue("Goodbye, Bobby. Catch you next time.")
        await asyncio.sleep(0.5)
        return True

    signals.set_state("thinking")

    async def on_sentence(sentence: str):
        await mouth.enqueue(sentence)

    # CRITICAL: a turn that raises must not take the voice line down with it.
    # Catching `Exception` was NOT enough — the app still died on 2026-09-18
    # with the fix loaded. asyncio.CancelledError and BaseExceptionGroup both
    # inherit from BaseException, and the SDK runs its transport inside an
    # anyio task group, so a transport failure arrives as one of those and
    # sails straight past `except Exception`.
    #
    # So: catch BaseException, and re-raise only the three that genuinely mean
    # "stop the program" — Ctrl-C, sys.exit, and a real cancellation.
    try:
        await brain.turn(text, on_sentence=on_sentence)
    except (KeyboardInterrupt, SystemExit):
        raise
    except asyncio.CancelledError as e:
        log_crash("turn-cancelled", e)
        raise
    except BaseException as e:
        log_crash("turn", e)
        signals.set_state("idle")
        sys.stdout.write(f"\n[turn failed] {type(e).__name__}: {e}\n")
        sys.stdout.write(f"[traceback written to {CRASH_LOG}]\n")
        sys.stdout.flush()
        await mouth.enqueue("That one broke on my end. Say it again and I'll take another run at it.")
    return False


# ── Main loop ────────────────────────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="Voice Line — talk to Claude")
    parser.add_argument("--open-mic", action="store_true", help="VAD-based open mic mode")
    parser.add_argument("--cwd", default=None, help="Working directory for Claude session")
    parser.add_argument(
        "--input-device",
        default=None,
        help="Mic index or name substring (e.g. 'iPhone'). Env: VOICE_INPUT_DEVICE",
    )
    parser.add_argument(
        "--list-devices", action="store_true", help="List input devices and exit"
    )
    args = parser.parse_args()

    if args.list_devices:
        print(ears_mod.list_devices())
        return

    try:
        ears = Ears(device=args.input_device)
    except ValueError as e:
        print(f"[error] {e}\n")
        print(ears_mod.list_devices())
        return

    print("╔══════════════════════════════════════╗")
    print("║         VOICE LINE — Lefty           ║")
    print("╠══════════════════════════════════════╣")
    print("║  Hold Right Ctrl to talk             ║")
    print("║  Type in this terminal (Enter sends) ║")
    print("║  Say 'goodbye' to quit               ║")
    print("║  Ctrl-C also quits                   ║")
    print("╚══════════════════════════════════════╝")
    print()

    # Mic preflight — a muted device otherwise fails silently, turn after turn
    rms, alive = ears.check_level()
    print(f"[mic] {ears.device_name} (rms {rms})")
    if not alive:
        print("[mic] WARNING: no signal — mic may be muted or disconnected.")
        print("[mic] Pick another with --input-device NAME, or --list-devices.")
    print()

    # Initialize components. Mouth first: the consent gate speaks through it.
    # Brain is built after listen_ptt exists, because the gate answers through
    # push-to-talk and Brain needs the finished gate at construction time.
    mouth = Mouth()

    # Wire up Spotify ducking
    mouth.set_speaking_callback(ducking.on_speaking_change)

    loop = asyncio.get_event_loop()
    ptt = PushToTalk(loop)

    # PTT state
    mic_open = False
    pending_press = False  # a press consumed by an interrupt, owed to the mic
    ptt_event = asyncio.Event()
    ptt_action = None  # "pressed" or "released"

    def on_ptt_press():
        nonlocal ptt_action
        if mouth.is_speaking:
            mouth.interrupt()
            signals.set_state("idle")
        ptt_action = "pressed"
        ptt_event.set()

    def on_ptt_release():
        nonlocal ptt_action
        ptt_action = "released"
        ptt_event.set()

    def on_ptt_interrupt():
        if mouth.is_speaking:
            mouth.interrupt()
            signals.set_state("idle")

    async def _await_ptt(want: str):
        """Block until the PTT callback reports `want` ("pressed"/"released").

        Clear-then-wait is safe: both run in one synchronous block before any
        yield, and the callbacks post through call_soon_threadsafe, so a press
        cannot slip in between the clear and the wait.
        """
        while True:
            ptt_event.clear()
            await ptt_event.wait()
            if ptt_action == want:
                return

    async def listen_ptt() -> str:
        """Hold-to-talk capture for the consent gate.

        CRITICAL: the gate used to call ears.listen_open_mic(), which ends a
        turn only after 800ms of VAD-silence. On a hot mic the room never goes
        that quiet, so the call either ran past the approval timeout or handed
        whisper pure noise and got "" back. Either way Bobby's spoken "yes"
        was thrown away. Push-to-talk has no endpoint to guess: the key down
        and the key up ARE the boundaries.

        Safe to consume ptt_event here -- the main loop is parked inside
        brain.turn() for the whole life of an approval and is not racing us.
        """
        nonlocal mic_open
        await _await_ptt("pressed")

        mic_open = True
        signals.set_state("listening")
        ears.start_listening()

        await _await_ptt("released")

        mic_open = False
        return await ears.transcribe(ears.stop_listening())

    brain = Brain(
        cwd=args.cwd,
        can_use_tool=consent.make_voice_consent(mouth, listen_ptt),
    )

    ptt.set_callbacks(on_ptt_press, on_ptt_release, on_ptt_interrupt)
    ptt.start()

    # A background task that dies takes its traceback with it. Route those to
    # the crash log too — a dead mouth.run() is otherwise invisible.
    loop.set_exception_handler(
        lambda _loop, ctx: log_crash(
            "asyncio:" + str(ctx.get("message")),
            ctx.get("exception") or RuntimeError(str(ctx)),
        )
    )

    # Start mouth playback loop
    mouth_task = asyncio.create_task(mouth.run())

    # Enter raw terminal mode — typed input needs a real TTY, voice does not
    typed_input = _enter_raw()
    if not typed_input:
        print("[note] No TTY — typed input off. Hold Right Ctrl to talk.\n")

    try:
        # Warmup — prime the prompt cache, speak greeting
        print("[warming up Claude session...]")
        signals.set_state("thinking")
        try:
            await brain.warmup(on_sentence=mouth.enqueue)
            print("[ready]\n")
        except Exception as e:
            # A failed warmup only costs the cache prime. Don't die over it.
            print(f"[warmup failed] {type(e).__name__}: {e} — continuing cold.\n")

        # Prompt
        sys.stdout.write("you> ")
        sys.stdout.flush()

        while True:
            if args.open_mic:
                # Open-mic mode: VAD-based
                if not mouth.is_speaking:
                    signals.set_state("listening")
                    text = await ears.listen_open_mic()
                    if text:
                        sys.stdout.write(f"\r[heard] {text}\n")
                        sys.stdout.flush()
                        # open-mic has no key to press, but the busy latch
                        # still matters so the visualizer stays honest
                        signals.set_busy(True)
                        try:
                            quit = await handle_turn(text, brain, mouth)
                        finally:
                            signals.set_busy(False)
                        if quit:
                            break
                        sys.stdout.write("you> ")
                        sys.stdout.flush()
                else:
                    await asyncio.sleep(0.1)
            else:
                # Hold-to-talk + typed input mode
                # An interrupt already consumed a press and the key is still
                # down. Skip the race and go straight to listening.
                if pending_press:
                    pending_press = False
                    if not ptt.is_held:
                        # He already let go while the turn was cancelling.
                        # Opening the mic now would wait for a release that has
                        # been and gone, which is why it took several presses to
                        # get anywhere. Fall through to the normal wait instead.
                        sys.stdout.write("\r[go ahead]        \n")
                        sys.stdout.flush()
                        signals.set_state("idle")
                    else:
                        ptt_action = "pressed"
                        mic_open = True
                        sys.stdout.write("\r🎤 listening...\r")
                        sys.stdout.flush()
                        signals.set_state("listening")
                        ears.start_listening()
                        ptt_event.clear()
                        await ptt_event.wait()          # the release
                        wav = ears.stop_listening()
                        mic_open = False
                        sys.stdout.write("\r              \r")
                        sys.stdout.flush()
                        if wav:
                            signals.set_state("thinking")
                            text = await ears.transcribe(wav)
                            if text:
                                sys.stdout.write(f"[you] {text}\n")
                                sys.stdout.flush()
                                quit, interrupted = await run_turn_interruptible(
                                    text, brain, mouth, ptt_event, lambda: ptt_action,
                                )
                                if quit:
                                    break
                                if interrupted:
                                    pending_press = True
                        sys.stdout.write("you> ")
                        sys.stdout.flush()
                    continue

                # Race: PTT event vs typed input
                ptt_event.clear()

                ptt_future = asyncio.ensure_future(ptt_event.wait())
                # Without a TTY there is no line editor to race — PTT only.
                typed_future = (
                    asyncio.ensure_future(_read_line_raw()) if typed_input else None
                )

                done, pending = await asyncio.wait(
                    {typed_future, ptt_future} if typed_future else {ptt_future},
                    return_when=asyncio.FIRST_COMPLETED,
                )

                if typed_future is not None and typed_future in done:
                    # Keep ptt_future alive for next iteration
                    ptt_future.cancel()
                    text = typed_future.result()
                    if text:
                        quit, _interrupted = await run_turn_interruptible(
                            text, brain, mouth, ptt_event, lambda: ptt_action,
                        )
                        if quit:
                            break
                    sys.stdout.write("you> ")
                    sys.stdout.flush()

                elif ptt_future in done:
                    # PTT event fired — drop the pending line read
                    if typed_future is not None:
                        typed_future.cancel()

                    if ptt_action == "pressed":
                        # Start recording
                        mic_open = True
                        sys.stdout.write("\r🎤 listening...\r")
                        sys.stdout.flush()
                        signals.set_state("listening")
                        ears.start_listening()

                        # Wait for release
                        ptt_event.clear()
                        await ptt_event.wait()

                    if ptt_action == "released" and mic_open:
                        mic_open = False
                        wav = ears.stop_listening()
                        sys.stdout.write("\r              \r")
                        sys.stdout.flush()

                        if wav:
                            signals.set_state("thinking")
                            sys.stdout.write("[transcribing...]\r")
                            sys.stdout.flush()
                            text = await ears.transcribe(wav)
                            sys.stdout.write("                  \r")
                            sys.stdout.flush()

                            if text:
                                sys.stdout.write(f"[you] {text}\n")
                                sys.stdout.flush()
                                quit, interrupted = await run_turn_interruptible(
                                    text, brain, mouth, ptt_event,
                                    lambda: ptt_action,
                                )
                                if quit:
                                    break
                                if interrupted:
                                    # Bobby cut in and IS STILL HOLDING THE KEY.
                                    # pynput only fires on transitions, so no
                                    # fresh press event is coming. Looping back
                                    # to wait for one would hang until he
                                    # pressed a second time. Latch it instead.
                                    pending_press = True
                                    continue

                        sys.stdout.write("you> ")
                        sys.stdout.flush()

    except (KeyboardInterrupt, EOFError):
        print("\n[quitting]")
    except BaseException as e:
        # Anything that escapes the loop is a bug. Record it before unwinding,
        # because the launcher's cleanup wipes the terminal past reading.
        log_crash("main-loop", e)
        print(f"\n[voice line crashed] {type(e).__name__}: {e}")
        print(f"[traceback written to {CRASH_LOG}]")
        raise
    finally:
        _restore_terminal()
        ptt.stop()
        mouth.interrupt()
        await mouth.enqueue(None)  # signal mouth loop to exit
        await mouth.close()
        await ears.close()
        signals.cleanup()
        ducking.restore_now()
        print("Voice Line closed.")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        pass
    except BaseException as e:
        # Last net. Covers anything that blows up before or after the loop.
        log_crash("toplevel", e)
        print(f"\n[voice line crashed] {type(e).__name__}: {e}")
        print(f"[traceback written to {CRASH_LOG}]")
        raise
