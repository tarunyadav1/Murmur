#!/usr/bin/env python3
"""
Chatterbox TTS Server for Murmur
Provides HTTP API for text-to-speech with emotion control and voice cloning
"""

import os
import io
import json
import base64
import logging
from typing import Optional
from contextlib import asynccontextmanager
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global model instance
model = None
SAMPLE_RATE = 24000

# Voice library paths - check multiple locations
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent

# Possible locations for voice samples (in order of preference)
VOICE_SAMPLE_PATHS = [
    # Environment variable (set by app - highest priority, most reliable)
    Path(os.environ.get("MURMUR_VOICE_SAMPLES_DIR", "")) if os.environ.get("MURMUR_VOICE_SAMPLES_DIR") else None,
    # Application Support location (copied during setup)
    PROJECT_DIR / "VoiceSamples",
    # Development location
    PROJECT_DIR / "Resources" / "VoiceSamples",
]

def find_voice_samples_dir() -> Optional[Path]:
    """Find the voice samples directory from multiple possible locations"""
    for path in VOICE_SAMPLE_PATHS:
        if path and path.exists() and (path / "voices.json").exists():
            logger.info(f"Found voice samples at: {path}")
            return path
    logger.warning("Voice samples directory not found in any expected location")
    return None

VOICE_SAMPLES_DIR = find_voice_samples_dir() or (PROJECT_DIR / "VoiceSamples")
VOICES_JSON_PATH = VOICE_SAMPLES_DIR / "voices.json"

# Cached voice library
voice_library: dict = {}


def load_voice_library():
    """Load voice library from voices.json"""
    global voice_library

    if not VOICES_JSON_PATH.exists():
        logger.warning(f"Voice library not found at {VOICES_JSON_PATH}")
        return

    try:
        with open(VOICES_JSON_PATH, 'r') as f:
            data = json.load(f)
            voice_library = {v['id']: v for v in data.get('voices', [])}
            logger.info(f"Loaded {len(voice_library)} voices from library")
    except Exception as e:
        logger.error(f"Failed to load voice library: {e}")


def get_voice_audio_path(voice_id: str) -> Optional[str]:
    """Get the audio file path for a voice ID"""
    if voice_id not in voice_library:
        return None

    voice = voice_library[voice_id]
    audio_path = VOICE_SAMPLES_DIR / voice['file']

    if audio_path.exists():
        return str(audio_path)

    logger.warning(f"Voice sample file not found: {audio_path}")
    return None


class TTSRequest(BaseModel):
    """Request model for TTS generation"""
    text: str = Field(..., min_length=1, max_length=10000)
    exaggeration: float = Field(default=0.5, ge=0.0, le=1.0, description="Emotion/energy intensity")
    cfg_weight: float = Field(default=0.5, ge=0.0, le=1.0, description="Voice match strength")
    speed: float = Field(default=1.0, ge=0.5, le=2.0, description="Playback speed")
    voice_id: Optional[str] = Field(default=None, description="Voice preset ID")
    audio_prompt_path: Optional[str] = Field(default=None, description="Path to reference audio for voice cloning")


class TTSResponse(BaseModel):
    """Response model for TTS generation"""
    audio_base64: str
    sample_rate: int
    duration_seconds: float
    format: str = "wav"


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    model_loaded: bool
    device: str


def apply_fade_out(audio: np.ndarray, fade_length: float, sample_rate: int) -> np.ndarray:
    """Apply fade-out effect to audio"""
    if fade_length <= 0:
        return audio

    fade_samples = int(fade_length * sample_rate)
    if fade_samples >= len(audio):
        fade_samples = len(audio)

    fade_curve = np.linspace(1.0, 0.0, fade_samples)
    audio[-fade_samples:] = audio[-fade_samples:] * fade_curve
    return audio


def apply_speed_change(audio: np.ndarray, speed: float, sample_rate: int) -> tuple[np.ndarray, int]:
    """Apply speed change by resampling (simple method)"""
    if speed == 1.0:
        return audio, sample_rate

    # For speed changes, we adjust the sample rate interpretation
    # This is a simple approach; for better quality, use librosa or scipy
    new_sample_rate = int(sample_rate * speed)
    return audio, new_sample_rate


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model and voice library on startup, cleanup on shutdown"""
    global model

    # Load voice library first
    logger.info("Loading voice library...")
    load_voice_library()

    logger.info("Loading Chatterbox TTS model...")

    try:
        from chatterbox.tts import ChatterboxTTS

        # Determine device
        if torch.backends.mps.is_available():
            device = "mps"
        elif torch.cuda.is_available():
            device = "cuda"
        else:
            device = "cpu"

        logger.info(f"Using device: {device}")
        model = ChatterboxTTS.from_pretrained(device=device)
        logger.info("Chatterbox model loaded successfully!")

    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        model = None

    yield

    # Cleanup
    logger.info("Shutting down TTS server...")
    model = None


app = FastAPI(
    title="Murmur TTS Server",
    description="Chatterbox TTS backend for Murmur app",
    version="1.0.0",
    lifespan=lifespan
)

# Allow CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Check server and model status"""
    device = "unknown"
    if torch.backends.mps.is_available():
        device = "mps"
    elif torch.cuda.is_available():
        device = "cuda"
    else:
        device = "cpu"

    return HealthResponse(
        status="ok" if model is not None else "model_not_loaded",
        model_loaded=model is not None,
        device=device
    )


@app.post("/generate", response_model=TTSResponse)
async def generate_speech(request: TTSRequest):
    """Generate speech from text with style parameters and voice cloning"""
    global model

    if model is None:
        raise HTTPException(status_code=503, detail="TTS model not loaded")

    try:
        # Determine audio prompt path for voice cloning
        audio_prompt_path = request.audio_prompt_path

        # If voice_id is provided, look up the voice sample path
        if request.voice_id and not audio_prompt_path:
            audio_prompt_path = get_voice_audio_path(request.voice_id)
            if audio_prompt_path:
                logger.info(f"Using voice sample: {audio_prompt_path}")

        logger.info(f"Generating speech: text='{request.text[:50]}...', "
                   f"exaggeration={request.exaggeration}, cfg_weight={request.cfg_weight}, "
                   f"voice_id={request.voice_id}")

        # Generate audio with Chatterbox
        wav = model.generate(
            text=request.text,
            exaggeration=request.exaggeration,
            cfg_weight=request.cfg_weight,
            audio_prompt_path=audio_prompt_path
        )

        # Convert tensor to numpy
        if hasattr(wav, 'cpu'):
            audio_np = wav.cpu().numpy()
        else:
            audio_np = np.array(wav)

        # Ensure 1D array
        if audio_np.ndim > 1:
            audio_np = audio_np.squeeze()

        # Apply speed change if needed
        output_sample_rate = SAMPLE_RATE
        if request.speed != 1.0:
            audio_np, output_sample_rate = apply_speed_change(audio_np, request.speed, SAMPLE_RATE)

        # Calculate duration
        duration = len(audio_np) / output_sample_rate

        # Convert to WAV bytes
        buffer = io.BytesIO()
        sf.write(buffer, audio_np, output_sample_rate, format='WAV')
        buffer.seek(0)

        # Encode to base64
        audio_base64 = base64.b64encode(buffer.read()).decode('utf-8')

        logger.info(f"Generated {duration:.2f}s of audio")

        return TTSResponse(
            audio_base64=audio_base64,
            sample_rate=output_sample_rate,
            duration_seconds=duration,
            format="wav"
        )

    except Exception as e:
        logger.error(f"Generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/voices")
async def list_voices():
    """List available voice presets from the voice library"""
    # Return voices from the loaded voice library
    voices = []

    for voice_id, voice_data in voice_library.items():
        voices.append({
            "id": voice_id,
            "name": voice_data.get("name", voice_id),
            "description": voice_data.get("description", ""),
            "gender": voice_data.get("gender", "unknown"),
            "style": voice_data.get("style", "general"),
            "has_sample": get_voice_audio_path(voice_id) is not None
        })

    # Add a "default" option for no voice cloning
    voices.insert(0, {
        "id": "default",
        "name": "Default",
        "description": "Default Chatterbox voice (no cloning)",
        "gender": "neutral",
        "style": "default",
        "has_sample": False
    })

    return {
        "voices": voices,
        "supports_cloning": True,
        "voice_samples_path": str(VOICE_SAMPLES_DIR)
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8787))
    host = os.environ.get("HOST", "127.0.0.1")

    uvicorn.run(
        "server:app",
        host=host,
        port=port,
        reload=False,
        log_level="info"
    )
