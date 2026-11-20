"""Phone line — talk to your agent from your phone, with the visualizer as the face.

Built 2026-11-15 (Lefty) because nothing first-party does two-way VOICE with a local
agent: Anthropic's Remote Control is text-only and Claude Code has no spoken replies.

How it works: the phone opens this page over HTTPS, holds a button, and records.
The audio comes here, gets transcribed by the SAME whisper-server the voice line uses,
goes to a Brain (same code, its OWN session file so it never collides with the desk
voice line), and each reply sentence is voiced by the SAME Mouth synthesis
(ElevenLabs, Kokoro fallback) and sent back to the phone to play. The visualizer page
is served unchanged; the phone feeds it state + level from what it is playing.

Nothing here is exposed to the internet. It listens on the LAN (and later Tailscale),
and every request needs the access key printed at startup.
"""

import asyncio
import io
import json
import os
import secrets
import subprocess
import sys
import time
import uuid
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
VOICE_LINE = HERE.parent
# The visualizer ships in this repo next to voice-line/. Override with PHONE_VIZ_DIR.
VIZ_DIR = Path(os.environ.get("PHONE_VIZ_DIR", VOICE_LINE.parent / "visualizer"))
sys.path.insert(0, str(VOICE_LINE))

import httpx  # noqa: E402
from fastapi import FastAPI, Request, Response  # noqa: E402
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse, FileResponse  # noqa: E402
from claude_agent_sdk import PermissionResultAllow, PermissionResultDeny  # noqa: E402

import brain as brain_mod  # noqa: E402

# Own session. The desk voice line holds .voice_session; two processes resuming the
# same session at once would interleave turns into one transcript.
brain_mod.SESSION_FILE = HERE / ".phone_session"
# Normal sentences are brain.py's default now, for every spoken channel. Setting it here
# only (2026-11-15) left the desk line talking in clipped fragments for five more days.
from brain import Brain  # noqa: E402
import consent  # noqa: E402  (reuse its vault exemption, wording and audit log)
from mouth import Mouth  # noqa: E402

WHISPER_URL = os.environ.get("PHONE_WHISPER_URL", "http://localhost:2022/inference")
TOKEN_FILE = HERE / ".token"
APPROVAL_TIMEOUT_S = 90
PHONE_HINT = (
    "\n(This turn came from the user's phone, by voice. They may be walking or driving: keep it "
    "short, and anything long goes in a file, not read aloud.)"
)


def load_token() -> str:
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text().strip()
    tok = secrets.token_urlsafe(18)
    TOKEN_FILE.write_text(tok)
    os.chmod(TOKEN_FILE, 0o600)
    return tok


TOKEN = load_token()
app = FastAPI()

# ── shared state ────────────────────────────────────────────────────────────
STATE = {"state": "idle", "since": time.time()}
AUDIO: dict[str, bytes] = {}          # id -> wav bytes, dropped after fetch or 10 min
AUDIO_AT: dict[str, float] = {}
SUBSCRIBERS: dict[str, asyncio.Queue] = {}   # client id -> its event queue
# Which page gets the AUDIO. Set by whichever client sent the current turn.
ACTIVE = {"cid": None}
PENDING: dict[str, asyncio.Future] = {}
TURN_LOCK = asyncio.Lock()
mouth = Mouth()
http = httpx.AsyncClient(timeout=60.0)


def set_state(s: str):
    STATE["state"] = s
    STATE["since"] = time.time()
    emit({"type": "state", "state": s})


def emit(ev: dict):
    for q in list(SUBSCRIBERS.values()):
        q.put_nowait(ev)


def speaking_cid() -> str | None:
    """The one page allowed to play audio this turn.

    WHY THIS EXISTS — the symptom was a double voice on the phone, 2026-11-16.
    `say` used to broadcast the audio id to EVERY open page, and `/audio/<id>`
    deletes the clip on first fetch. With two pages open (iOS Safari keeps a
    backgrounded tab's EventSource alive, and every reconnect added another
    subscriber) the two raced for the same clip: the winner played sentence 1, the
    loser got a 404, fell through to playNext() and played sentence 2. Two voices,
    out of step, reading different halves of one reply. It sounds like an echo; it
    is actually the reply being split across tabs.

    Fix: audio is addressed to one client. Every other page gets the text only.
    """
    cid = ACTIVE["cid"]
    if cid in SUBSCRIBERS:
        return cid
    # The sender reconnected (new cid) or never identified itself: fall back to the
    # newest page, which is the one being looked at.
    return next(reversed(SUBSCRIBERS), None) if SUBSCRIBERS else None


def authed(req: Request) -> bool:
    k = req.cookies.get("lk") or req.headers.get("x-lefty-key") or req.query_params.get("k")
    return bool(k) and secrets.compare_digest(k, TOKEN)


def deny():
    return Response("Locked. Open the link with the access key once on this phone.", 401)


def pcm_to_wav(pcm: bytes, rate: int) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    return buf.getvalue()


def gc_audio():
    cut = time.time() - 600
    for k in [k for k, t in AUDIO_AT.items() if t < cut]:
        AUDIO.pop(k, None)
        AUDIO_AT.pop(k, None)


# ── tool approval, on the phone ─────────────────────────────────────────────
async def phone_consent(tool_name, input_data, context):
    if tool_name in consent._WRITE_TOOLS:
        target = (input_data or {}).get("file_path") or (input_data or {}).get("notebook_path")
        if consent._inside_vault(target):
            consent._audit(f"AUTO  {tool_name}: {target} (inside vault, phone)")
            return PermissionResultAllow()
    what = consent._describe(tool_name, input_data, context)
    ask_id = uuid.uuid4().hex[:10]
    fut = asyncio.get_running_loop().create_future()
    PENDING[ask_id] = fut
    consent._audit(f"ASK   {what} (phone)")
    emit({"type": "ask", "id": ask_id, "text": what})
    await say(f"I need your okay for this: {what}")
    prev = STATE["state"]
    set_state("listening")
    try:
        yes = await asyncio.wait_for(fut, APPROVAL_TIMEOUT_S)
    except asyncio.TimeoutError:
        yes = None
    finally:
        PENDING.pop(ask_id, None)
        set_state(prev)
    if yes:
        consent._audit(f"YES   {what} (phone)")
        return PermissionResultAllow()
    consent._audit(f"NO    {what} (phone, {'timeout' if yes is None else 'tapped no'})")
    return PermissionResultDeny(
        message="Not approved on the phone." if yes is False
        else "No answer from the phone in time, so not approved."
    )


brain = Brain(can_use_tool=phone_consent)


# Diagnostic trail. Two wrong fixes for a "double voice" went out on 2026-11-16
# because "it sounds fixed" was treated as evidence. This log answers the only
# question that matters: was each sentence SENT once, and FETCHED once?
#   SAY   lines = what the agent asked to be spoken (duplicates here = agent side)
#   AUDIO lines = what the page actually pulled (more pulls than says = page side)
SAY_N = {"turn": 0, "i": 0}


async def say(sentence: str):
    """Voice one sentence and push it to the phone that asked. Others get text only."""
    sentence = sentence.strip()
    if not sentence:
        return
    pcm, rate = await mouth._synthesize(sentence)
    talker = speaking_cid()
    aid = uuid.uuid4().hex[:12] if (pcm and talker) else None
    if aid:
        AUDIO[aid] = pcm_to_wav(pcm, rate)
        AUDIO_AT[aid] = time.time()
    SAY_N["i"] += 1
    print(f"[phone] SAY turn={SAY_N['turn']} n={SAY_N['i']} id={aid} "
          f"cid={talker} subs={len(SUBSCRIBERS)} text={sentence[:70]!r}", flush=True)
    for cid, q in list(SUBSCRIBERS.items()):
        q.put_nowait({"type": "say", "text": sentence,
                      "id": aid if cid == talker else None})


async def run_turn(text: str):
    async with TURN_LOCK:
        SAY_N["turn"] += 1
        SAY_N["i"] = 0
        print(f"[phone] TURN {SAY_N['turn']} start, subs={len(SUBSCRIBERS)}, "
              f"active={ACTIVE['cid']}", flush=True)
        emit({"type": "heard", "text": text})
        set_state("thinking")
        try:
            if brain.is_quit(text):
                await say("Okay. I'm here whenever you need me.")
            else:
                await brain.turn(text + PHONE_HINT, on_sentence=say)
        except Exception as e:  # never go silent on the phone
            print(f"[phone] turn failed: {e!r}", flush=True)
            await say("That one broke on my end. Try me again.")
        finally:
            set_state("idle")
            emit({"type": "done"})
            gc_audio()


async def transcribe(raw: bytes) -> str:
    proc = await asyncio.create_subprocess_exec(
        "ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-ar", "16000", "-ac", "1",
        "-f", "wav", "pipe:1",
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    wav, err = await proc.communicate(raw)
    if proc.returncode != 0 or not wav:
        raise RuntimeError(f"ffmpeg could not read the phone audio: {err.decode()[:200]}")
    r = await http.post(WHISPER_URL, files={"file": ("phone.wav", wav, "audio/wav")},
                        data={"response_format": "json", "temperature": "0"})
    r.raise_for_status()
    return (r.json().get("text") or "").strip()


# ── routes ──────────────────────────────────────────────────────────────────
@app.get("/")
async def index(req: Request):
    if not authed(req):
        return deny()
    # no-store so a fix to app.html lands on the next reload. Without it Safari served
    # a cached page and a client-side fix looked like it had not been applied (2026-11-16).
    resp = HTMLResponse((HERE / "app.html").read_text(),
                        headers={"Cache-Control": "no-store"})
    if req.query_params.get("k"):
        resp.set_cookie("lk", TOKEN, max_age=60 * 60 * 24 * 365, httponly=True,
                        secure=True, samesite="strict")
    return resp


@app.get("/manifest.json")
async def manifest():
    return JSONResponse({"name": "Lefty", "short_name": "Lefty", "start_url": "/",
                         "display": "standalone", "background_color": "#000000",
                         "theme_color": "#000000"})


@app.get("/viz/")
async def viz(req: Request):
    if not authed(req):
        return deny()
    return FileResponse(VIZ_DIR / "index.html", headers={"Cache-Control": "no-store"})


@app.get("/viz/assets/{name}")
async def viz_asset(name: str, req: Request):
    if not authed(req) or "/" in name or name.startswith("."):
        return deny()
    # Every asset here is OPTIONAL — the visualizer draws its face procedurally and
    # only swaps in assets/face.png if you drop one there. FileResponse on a missing
    # path raises inside the response, so a stock install (no face.png) fills the
    # error log with full tracebacks for a file that is not meant to exist. Answer
    # 404 and let the page's img.onerror keep the procedural face.
    path = VIZ_DIR / "assets" / name
    if not path.is_file():
        return JSONResponse({"error": "not found"}, status_code=404)
    return FileResponse(path)


@app.get("/state")
async def state(req: Request):
    # The visualizer polls this. The phone overrides level/samples from what it plays.
    return JSONResponse({"state": STATE["state"], "level": 0.0, "alert": None, "samples": []})


@app.post("/talk")
async def talk(req: Request):
    if not authed(req):
        return deny()
    if TURN_LOCK.locked():
        return JSONResponse({"ok": False, "why": "busy"}, 409)
    raw = await req.body()
    if len(raw) < 1500:
        return JSONResponse({"ok": False, "why": "too short"})
    ACTIVE["cid"] = req.headers.get("x-lefty-cid")
    print(f"[phone] TALK from page={req.headers.get('x-lefty-page')} "
          f"cid={ACTIVE['cid']}", flush=True)
    set_state("thinking")
    try:
        text = await transcribe(raw)
    except Exception as e:
        set_state("idle")
        print(f"[phone] transcribe failed: {e!r}", flush=True)
        return JSONResponse({"ok": False, "why": "could not hear that"})
    if not text or text.lower().strip(" .") in ("", "[blank_audio]", "you"):
        set_state("idle")
        return JSONResponse({"ok": False, "why": "heard nothing"})
    asyncio.create_task(run_turn(text))
    return JSONResponse({"ok": True, "heard": text})


@app.post("/type")
async def typed(req: Request):
    if not authed(req):
        return deny()
    if TURN_LOCK.locked():
        return JSONResponse({"ok": False, "why": "busy"}, 409)
    text = ((await req.json()).get("text") or "").strip()
    if not text:
        return JSONResponse({"ok": False})
    ACTIVE["cid"] = req.headers.get("x-lefty-cid")
    asyncio.create_task(run_turn(text))
    return JSONResponse({"ok": True})


@app.post("/answer")
async def answer(req: Request):
    if not authed(req):
        return deny()
    body = await req.json()
    fut = PENDING.get(body.get("id"))
    if fut and not fut.done():
        fut.set_result(bool(body.get("yes")))
        return JSONResponse({"ok": True})
    return JSONResponse({"ok": False})


@app.get("/audio/{aid}")
async def audio(aid: str, req: Request):
    if not authed(req):
        return deny()
    data = AUDIO.pop(aid, None)
    AUDIO_AT.pop(aid, None)
    print(f"[phone] AUDIO fetch id={aid} hit={data is not None} "
          f"page={req.headers.get('x-lefty-page')}", flush=True)
    if data is None:
        return Response(status_code=404)
    return Response(data, media_type="audio/wav", headers={"Cache-Control": "no-store"})


@app.get("/events")
async def events(req: Request):
    if not authed(req):
        return deny()
    cid = uuid.uuid4().hex[:12]
    q: asyncio.Queue = asyncio.Queue()
    SUBSCRIBERS[cid] = q
    # The page stores this and sends it back on /talk and /type, so the reply audio
    # goes to the page that asked instead of to every open tab. See speaking_cid().
    q.put_nowait({"type": "hello", "cid": cid})
    q.put_nowait({"type": "state", "state": STATE["state"]})

    async def gen():
        try:
            while True:
                try:
                    ev = await asyncio.wait_for(q.get(), 15)
                    yield f"data: {json.dumps(ev)}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"   # keeps phones and proxies from dropping the stream
                if await req.is_disconnected():
                    break
        finally:
            SUBSCRIBERS.pop(cid, None)
            if ACTIVE["cid"] == cid:
                ACTIVE["cid"] = None

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


@app.get("/health")
async def health():
    return {"ok": True, "state": STATE["state"]}
