#!/usr/bin/env python3
"""
Kokoro TTS Server - Fast tier for Murmur
Uses MLX-accelerated Kokoro model (82M params) for instant TTS generation
"""

import os
import io
import base64
import logging
import time
from typing import Optional
from contextlib import asynccontextmanager

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global model instance
kokoro_model = None
SAMPLE_RATE = 24000

# All available Kokoro voices from https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md
KOKORO_VOICES = {
    # American Female
    "af_heart": {"name": "Heart", "gender": "female", "accent": "American", "description": "Default voice"},
    "af_alloy": {"name": "Alloy", "gender": "female", "accent": "American", "description": "Clear and articulate"},
    "af_aoede": {"name": "Aoede", "gender": "female", "accent": "American", "description": "Melodic tone"},
    "af_bella": {"name": "Bella", "gender": "female", "accent": "American", "description": "Warm and friendly"},
    "af_jessica": {"name": "Jessica", "gender": "female", "accent": "American", "description": "Professional"},
    "af_kore": {"name": "Kore", "gender": "female", "accent": "American", "description": "Youthful energy"},
    "af_nicole": {"name": "Nicole", "gender": "female", "accent": "American", "description": "Confident"},
    "af_nova": {"name": "Nova", "gender": "female", "accent": "American", "description": "Modern and fresh"},
    "af_river": {"name": "River", "gender": "female", "accent": "American", "description": "Calm and flowing"},
    "af_sarah": {"name": "Sarah", "gender": "female", "accent": "American", "description": "Natural and warm"},
    "af_sky": {"name": "Sky", "gender": "female", "accent": "American", "description": "Light and airy"},

    # American Male
    "am_adam": {"name": "Adam", "gender": "male", "accent": "American", "description": "Deep and authoritative"},
    "am_echo": {"name": "Echo", "gender": "male", "accent": "American", "description": "Resonant"},
    "am_eric": {"name": "Eric", "gender": "male", "accent": "American", "description": "Professional narrator"},
    "am_fenrir": {"name": "Fenrir", "gender": "male", "accent": "American", "description": "Strong and bold"},
    "am_liam": {"name": "Liam", "gender": "male", "accent": "American", "description": "Friendly and approachable"},
    "am_michael": {"name": "Michael", "gender": "male", "accent": "American", "description": "Trustworthy"},
    "am_onyx": {"name": "Onyx", "gender": "male", "accent": "American", "description": "Deep and smooth"},
    "am_puck": {"name": "Puck", "gender": "male", "accent": "American", "description": "Playful"},

    # British Female
    "bf_alice": {"name": "Alice", "gender": "female", "accent": "British", "description": "Elegant"},
    "bf_emma": {"name": "Emma", "gender": "female", "accent": "British", "description": "Classic British"},
    "bf_isabella": {"name": "Isabella", "gender": "female", "accent": "British", "description": "Refined"},
    "bf_lily": {"name": "Lily", "gender": "female", "accent": "British", "description": "Soft and gentle"},

    # British Male
    "bm_daniel": {"name": "Daniel", "gender": "male", "accent": "British", "description": "Distinguished"},
    "bm_fable": {"name": "Fable", "gender": "male", "accent": "British", "description": "Storyteller"},
    "bm_george": {"name": "George", "gender": "male", "accent": "British", "description": "Classic gentleman"},
    "bm_lewis": {"name": "Lewis", "gender": "male", "accent": "British", "description": "Warm British"},

    # Japanese Female
    "jf_alpha": {"name": "Alpha", "gender": "female", "accent": "Japanese", "description": "Clear Japanese"},
    "jf_gongitsune": {"name": "Gongitsune", "gender": "female", "accent": "Japanese", "description": "Traditional"},
    "jf_nezuko": {"name": "Nezuko", "gender": "female", "accent": "Japanese", "description": "Soft and gentle"},
    "jf_tebukuro": {"name": "Tebukuro", "gender": "female", "accent": "Japanese", "description": "Warm"},

    # Japanese Male
    "jm_kumo": {"name": "Kumo", "gender": "male", "accent": "Japanese", "description": "Deep Japanese"},

    # Chinese Female
    "zf_xiaobei": {"name": "Xiaobei", "gender": "female", "accent": "Chinese", "description": "Mandarin Chinese"},
    "zf_xiaoni": {"name": "Xiaoni", "gender": "female", "accent": "Chinese", "description": "Soft Mandarin"},
    "zf_xiaoxiao": {"name": "Xiaoxiao", "gender": "female", "accent": "Chinese", "description": "Natural Mandarin"},
    "zf_xiaoyi": {"name": "Xiaoyi", "gender": "female", "accent": "Chinese", "description": "Clear Mandarin"},

    # Chinese Male
    "zm_yunjian": {"name": "Yunjian", "gender": "male", "accent": "Chinese", "description": "Professional Mandarin"},
    "zm_yunxi": {"name": "Yunxi", "gender": "male", "accent": "Chinese", "description": "Warm Mandarin"},
    "zm_yunxia": {"name": "Yunxia", "gender": "male", "accent": "Chinese", "description": "Deep Mandarin"},
    "zm_yunyang": {"name": "Yunyang", "gender": "male", "accent": "Chinese", "description": "Natural Mandarin"},

    # Korean Female
    "kf_sarah": {"name": "Sarah (KR)", "gender": "female", "accent": "Korean", "description": "Korean female"},

    # Korean Male
    "km_kevin": {"name": "Kevin (KR)", "gender": "male", "accent": "Korean", "description": "Korean male"},

    # Spanish Female
    "ef_dora": {"name": "Dora", "gender": "female", "accent": "Spanish", "description": "Spanish female"},

    # Spanish Male
    "em_alex": {"name": "Alex", "gender": "male", "accent": "Spanish", "description": "Spanish male"},

    # French Female
    "ff_siwis": {"name": "Siwis", "gender": "female", "accent": "French", "description": "French female"},

    # Hindi Female
    "hf_alpha": {"name": "Alpha (HI)", "gender": "female", "accent": "Hindi", "description": "Hindi female"},
    "hf_beta": {"name": "Beta (HI)", "gender": "female", "accent": "Hindi", "description": "Hindi female alt"},

    # Hindi Male
    "hm_omega": {"name": "Omega (HI)", "gender": "male", "accent": "Hindi", "description": "Hindi male"},
    "hm_psi": {"name": "Psi (HI)", "gender": "male", "accent": "Hindi", "description": "Hindi male alt"},

    # Italian Female
    "if_sara": {"name": "Sara (IT)", "gender": "female", "accent": "Italian", "description": "Italian female"},

    # Italian Male
    "im_nicola": {"name": "Nicola", "gender": "male", "accent": "Italian", "description": "Italian male"},

    # Portuguese Female
    "pf_dora": {"name": "Dora (PT)", "gender": "female", "accent": "Portuguese", "description": "Brazilian Portuguese"},

    # Portuguese Male
    "pm_alex": {"name": "Alex (PT)", "gender": "male", "accent": "Portuguese", "description": "Brazilian Portuguese male"},
    "pm_santa": {"name": "Santa", "gender": "male", "accent": "Portuguese", "description": "Portuguese male"},
}


class TTSRequest(BaseModel):
    text: str = Field(..., description="Text to synthesize")
    voice: str = Field(default="af_heart", description="Voice ID to use")
    speed: float = Field(default=1.0, ge=0.5, le=2.0, description="Speech speed multiplier")


class TTSResponse(BaseModel):
    audio: str = Field(..., description="Base64 encoded WAV audio")
    sample_rate: int = Field(default=SAMPLE_RATE)
    duration: float = Field(..., description="Audio duration in seconds")
    generation_time: float = Field(..., description="Time to generate in seconds")
    real_time_factor: float = Field(..., description="Generation time / audio duration")


class VoiceInfo(BaseModel):
    id: str
    name: str
    gender: str
    accent: str
    description: str


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    device: str
    sample_rate: int
    voices_count: int


def load_kokoro():
    """Load the Kokoro model"""
    global kokoro_model

    logger.info("Loading Kokoro model (82M params)...")
    try:
        from mlx_audio.tts.generate import load_model
        kokoro_model = load_model("mlx-community/Kokoro-82M-bf16")
        logger.info("Kokoro model loaded successfully!")
        return True
    except Exception as e:
        logger.error(f"Failed to load Kokoro model: {e}")
        return False


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup"""
    load_kokoro()
    yield
    logger.info("Shutting down Kokoro server...")


app = FastAPI(
    title="Kokoro TTS Server",
    description="Fast TTS using MLX-accelerated Kokoro model",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Check server health and model status"""
    return HealthResponse(
        status="ok" if kokoro_model else "model_not_loaded",
        model_loaded=kokoro_model is not None,
        device="mps",  # MLX uses Metal/MPS
        sample_rate=SAMPLE_RATE,
        voices_count=len(KOKORO_VOICES)
    )


@app.get("/voices", response_model=list[VoiceInfo])
async def list_voices():
    """List all available Kokoro voices"""
    return [
        VoiceInfo(
            id=voice_id,
            name=info["name"],
            gender=info["gender"],
            accent=info["accent"],
            description=info["description"]
        )
        for voice_id, info in KOKORO_VOICES.items()
    ]


@app.post("/generate", response_model=TTSResponse)
async def generate_speech(request: TTSRequest):
    """Generate speech from text"""
    if not kokoro_model:
        raise HTTPException(status_code=503, detail="Model not loaded")

    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    voice = request.voice
    if voice not in KOKORO_VOICES:
        # Try to find a similar voice or use default
        voice = "af_heart"
        logger.warning(f"Unknown voice {request.voice}, using default: {voice}")

    try:
        start_time = time.time()

        # Generate audio using Kokoro
        audio_arrays = []
        for result in kokoro_model.generate(request.text, voice=voice, speed=request.speed):
            audio_arrays.append(np.array(result.audio))

        # Combine segments
        audio = np.concatenate(audio_arrays) if len(audio_arrays) > 1 else audio_arrays[0]

        generation_time = time.time() - start_time
        duration = len(audio) / SAMPLE_RATE

        # Convert to WAV bytes
        buffer = io.BytesIO()
        sf.write(buffer, audio, SAMPLE_RATE, format='WAV')
        buffer.seek(0)
        audio_base64 = base64.b64encode(buffer.read()).decode('utf-8')

        logger.info(f"Generated {duration:.2f}s audio in {generation_time:.2f}s ({duration/generation_time:.1f}x real-time)")

        return TTSResponse(
            audio=audio_base64,
            sample_rate=SAMPLE_RATE,
            duration=duration,
            generation_time=generation_time,
            real_time_factor=generation_time / duration if duration > 0 else 0
        )

    except Exception as e:
        logger.error(f"Generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8787)
