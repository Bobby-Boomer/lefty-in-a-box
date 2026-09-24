"""Spotify volume ducking via AppleScript (macOS).

While assistant speaks, drop Spotify volume to max(30, current * 0.6).
Restore with 1.2s debounce so back-to-back sentences don't yo-yo.
Never launch Spotify if it's not running.
"""

import asyncio
import subprocess
import platform

_DEBOUNCE_S = 1.2
_MIN_DUCKED_VOL = 30
_DUCK_FACTOR = 0.6

_original_volume: int | None = None
_restore_task: asyncio.Task | None = None
_is_macos = platform.system() == "Darwin"


def _run_applescript(script: str) -> str:
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip()
    except Exception:
        return ""


def _spotify_running() -> bool:
    if not _is_macos:
        return False
    result = _run_applescript(
        'tell application "System Events" to (name of processes) contains "Spotify"'
    )
    return result == "true"


def _get_spotify_volume() -> int:
    result = _run_applescript(
        'tell application "Spotify" to get sound volume'
    )
    try:
        return int(result)
    except ValueError:
        return 0


def _set_spotify_volume(vol: int):
    _run_applescript(
        f'tell application "Spotify" to set sound volume to {vol}'
    )


def _is_spotify_playing() -> bool:
    result = _run_applescript(
        'tell application "Spotify" to get player state as string'
    )
    return result == "playing"


def duck():
    """Duck Spotify volume if playing above threshold."""
    global _original_volume
    if not _is_macos or not _spotify_running():
        return
    if not _is_spotify_playing():
        return

    vol = _get_spotify_volume()
    if vol <= _MIN_DUCKED_VOL:
        return

    _original_volume = vol
    ducked = max(_MIN_DUCKED_VOL, int(vol * _DUCK_FACTOR))
    _set_spotify_volume(ducked)


def restore_now():
    """Restore Spotify volume immediately."""
    global _original_volume
    if _original_volume is not None and _is_macos and _spotify_running():
        _set_spotify_volume(_original_volume)
        _original_volume = None


async def restore_debounced():
    """Restore Spotify volume after debounce delay."""
    global _restore_task
    if _restore_task and not _restore_task.done():
        _restore_task.cancel()
    _restore_task = asyncio.current_task()
    await asyncio.sleep(_DEBOUNCE_S)
    restore_now()


def on_speaking_change(speaking: bool):
    """Callback for mouth speaking state changes."""
    if speaking:
        duck()
    else:
        loop = asyncio.get_event_loop()
        loop.create_task(restore_debounced())
