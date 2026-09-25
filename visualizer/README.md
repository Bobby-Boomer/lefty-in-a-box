# voice line // digital rain

A fullscreen Matrix digital-rain scene that reacts to the voice line running in
`../voice-line/` alongside it. Canvas 2D, vanilla JS, one self-contained HTML
file, no build step, no network, works offline.

It runs with or without the voice piece. **Without it the scene sits at `idle`,
which is correct rather than broken.**

## Run it

Double-click the **\<Name\> Screen** icon on the desktop, the one
`install/shortcuts.sh` (or `shortcuts.ps1`) created.

From a terminal it is `bin/visualizer.sh` on macOS and Linux,
`bin\visualizer.cmd` on Windows, both from the repo root. Those launchers find
this folder on their own; `start.sh` and `start.cmd` in here are what they call.

It starts `server.py` if port 8777 is cold (log: `$TMPDIR/voice-visualizer.log`),
then opens Chrome in kiosk mode on a throwaway profile so no tabs or extensions
ride along. Quit with **Cmd-Q** -- the server stays warm for next time.

The colour scheme comes from `look` in `lefty.config.json` at the repo root:
`rain`, `amber`, `ice`, `violet` or `mono`. `install/personalize.sh` writes it,
and `?look=amber` on the URL previews any of them without saving.

To stop the server: `kill $(lsof -ti tcp:8777)`

## The five states

| state | what the scene does |
|---|---|
| **idle** | sparse slow rain, deep green, no face. Screensaver. |
| **listening** | a subset of columns reverses and climbs *upward*, palette shifts cyan, a soft line sweeps bottom-to-top. Inbound attention. |
| **thinking** | full downpour, a decrypt scan bar sweeps the field scrambling glyphs and resolving them behind itself. |
| **speaking** | the face surfaces out of the code. The rain parts around the head, the face burns through, and brightness, bloom and the open mouth all ride the live voice level. |
| **alert** | whole field goes blood red, rain desyncs, horizontal glitch tears slice the frame, red pulses in from the edges. |

One eased `energy` value drives everything (attack ~0.5s, release ~1.0s).
`glowE` and `motionE` are separate axes off that same curve, so speaking gets
full glow at a calm cruise while thinking gets full speed.

## Keys

- **any key** -- skip the boot intro
- **F** -- FPS meter

A small state tag sits in the bottom-left corner at all times. If the server
stops answering it reads `no signal` and the scene eases itself back to idle.

## The server

`server.py` binds `127.0.0.1:8777`, serves this page, and serves `/state`:

```json
{"state": "idle|listening|thinking|speaking", "level": 0.0, "alert": false, "samples": []}
```

It reads the voice line's signal bus and is **strictly read-only** on it --
it never writes `.voice_state`, `.voice_waveform`, or `.voice_alert`.
Paths and tuning constants are at the top of the file.

**Stomp tolerance:** a waveform newer than 2 seconds means the voice is speaking
*right now*, whatever `.voice_state` says. `/state` reports `speaking` on a live
waveform, so a stray process overwriting the state file mid-sentence cannot cut
the show off.

`level` is `mean(abs(samples)) * LEVEL_GAIN` clamped to 0..1. If speech reads
too hot or too cold on your rig, `LEVEL_GAIN` at the top of `server.py` is the
one knob.

`samples` (the raw 64 floats) are passed through for anything that wants a real
oscilloscope. This scene doesn't use them.

## Testing without the voice line

Never write fake data onto the real bus -- two writers is chaos. Use these:

```bash
python3 server.py --mock        # port 8778, /state walks a scripted loop
```
Then open <http://127.0.0.1:8778/>. Same page, synthetic states and a breathing
voice level. This is also how to just enjoy the scene standalone.

URL switches (these simulate locally and never touch `/state` at all):

| url | what it does |
|---|---|
| `?mockstate=speaking` | hold any one state (`idle`/`listening`/`thinking`/`speaking`/`alert`) |
| `?mockstate=loop` | walk the same scripted loop the mock server uses |
| `?shot=speaking&t=1200` | render deterministically, advance 1200 ms, freeze. For screenshots. |
| `?shot=loop&t=29200` | freeze-frame anywhere in the scripted loop |
| `?facemask=1` | dev view: the face stencil as one grey block per glyph cell |

`?shot=` reseeds a fixed RNG and steps at a fixed 1/60s, so the same URL always
produces the same frame. It re-renders on resize, which matters because headless
Chrome fires a late resize that would otherwise clear the canvas.

## The face

Drawn procedurally in code -- no assets required, nothing to download.

To use your own instead, drop a `face.png` into `assets/` and reload. See
`assets/README.txt`; the loader crops to content and normalizes contrast so any
image lands at the right size and tonal range.
