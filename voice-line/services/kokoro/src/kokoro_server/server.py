"""Minimal OpenAI-compatible TTS server wrapping Kokoro."""

import io
import struct
import numpy as np
import soundfile as sf
from fastapi import FastAPI, Response
from pydantic import BaseModel
from contextlib import asynccontextmanager

_pipeline = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _pipeline
    from kokoro import KPipeline
    print("[kokoro] Loading pipeline (lang_code='a' for American English)...")
    _pipeline = KPipeline(lang_code="a")
    print("[kokoro] Ready.")
    yield

app = FastAPI(lifespan=lifespan)

class SpeechRequest(BaseModel):
    model: str = "kokoro"
    input: str
    voice: str = "af_heart"
    response_format: str = "pcm"
    speed: float = 1.0

@app.post("/v1/audio/speech")
async def speech(req: SpeechRequest):
    samples_list = []
    for _gs, _ps, audio in _pipeline(req.input, voice=req.voice, speed=req.speed):
        if audio is not None:
            samples_list.append(audio)
    if not samples_list:
        return Response(content=b"", media_type="audio/pcm")
    full = np.concatenate(samples_list)
    if req.response_format == "pcm":
        pcm = (full * 32767).astype(np.int16)
        return Response(content=pcm.tobytes(), media_type="audio/pcm")
    else:
        buf = io.BytesIO()
        sf.write(buf, full, 24000, format="WAV")
        return Response(content=buf.getvalue(), media_type="audio/wav")

@app.get("/health")
async def health():
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8880)
