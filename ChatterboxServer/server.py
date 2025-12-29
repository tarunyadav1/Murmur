#!/usr/bin/env python3
"""
Chatterbox TTS Server for Murmur
Provides HTTP API for text-to-speech with emotion control and voice cloning
Supports three tiers:
- Fast: Kokoro (82M params, MLX-based, ~10-30x real-time)
- Normal: Chatterbox Turbo (350M params, ~0.3x real-time)
- High Quality: Chatterbox Standard (500M params, ~0.1x real-time)
"""

import os
import io
import json
import base64
import logging
from typing import Optional, Literal
from contextlib import asynccontextmanager
from pathlib import Path
from enum import Enum

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ModelTier(str, Enum):
    FAST = "fast"           # Kokoro 82M (MLX)
    NORMAL = "normal"       # Chatterbox Turbo 350M
    HIGH_QUALITY = "high"   # Chatterbox Standard 500M


# Legacy enum for backwards compatibility
class ModelType(str, Enum):
    STANDARD = "standard"
    TURBO = "turbo"


# Global model instances
models = {
    ModelTier.FAST: None,       # Kokoro (mlx-audio)
    ModelTier.NORMAL: None,     # Chatterbox Turbo
    ModelTier.HIGH_QUALITY: None,  # Chatterbox Standard
}

# Track which models are available (downloaded)
model_availability = {
    ModelTier.FAST: False,
    ModelTier.NORMAL: False,
    ModelTier.HIGH_QUALITY: False,
}

current_device = "cpu"
SAMPLE_RATE = 24000
KOKORO_SAMPLE_RATE = 24000  # Kokoro also uses 24kHz

# Kokoro voices available
KOKORO_VOICES = {
    # US Female
    "af_bella": "Bella (US Female)",
    "af_nicole": "Nicole (US Female)",
    "af_sarah": "Sarah (US Female)",
    "af_sky": "Sky (US Female)",
    # UK Female
    "bf_emma": "Emma (UK Female)",
    "bf_isabella": "Isabella (UK Female)",
    # US Male
    "am_adam": "Adam (US Male)",
    "am_michael": "Michael (US Male)",
    # UK Male
    "bm_george": "George (UK Male)",
    "bm_lewis": "Lewis (UK Male)",
}

# Check if PyTorch is available (for Chatterbox models)
try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    logger.warning("PyTorch not available - Chatterbox models will be disabled")

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
    tier: ModelTier = Field(default=ModelTier.FAST, description="Quality tier: 'fast' (Kokoro), 'normal' (Turbo), 'high' (Standard)")
    # Legacy field for backwards compatibility
    model: Optional[ModelType] = Field(default=None, description="Legacy: 'standard' or 'turbo'")
    exaggeration: float = Field(default=0.5, ge=0.0, le=1.0, description="Emotion/energy intensity (high quality only)")
    cfg_weight: float = Field(default=0.5, ge=0.0, le=1.0, description="Voice match strength (high quality only)")
    speed: float = Field(default=1.0, ge=0.5, le=2.0, description="Playback speed")
    voice_id: Optional[str] = Field(default=None, description="Voice preset ID (Chatterbox) or Kokoro voice name")
    audio_prompt_path: Optional[str] = Field(default=None, description="Path to reference audio for voice cloning")


class TTSResponse(BaseModel):
    """Response model for TTS generation"""
    audio_base64: str
    sample_rate: int
    duration_seconds: float
    format: str = "wav"
    tier_used: str = "fast"
    model_used: str = "kokoro"  # Legacy compatibility


class TierStatus(BaseModel):
    """Status of a single tier"""
    available: bool  # Model is downloaded
    loaded: bool     # Model is loaded in memory


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    tiers: dict[str, TierStatus]
    device: str
    # Legacy fields for backwards compatibility
    models_loaded: dict[str, bool]
    available_models: list[str]


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


def load_kokoro_model():
    """Load Kokoro model (Fast tier) using mlx-audio

    NOTE: Currently disabled due to dependency conflict between
    mlx-audio (requires numpy>=1.26.4) and chatterbox-tts (requires numpy<1.26.0)
    """
    global models, model_availability

    logger.info("Checking Fast tier (Kokoro) availability...")
    try:
        from mlx_audio.tts.generate import generate_audio, load_model
        # Load the Kokoro model (use the bf16 version for better performance)
        kokoro_model = load_model("mlx-community/Kokoro-82M-bf16")
        # Store both the model and generate function
        models[ModelTier.FAST] = (kokoro_model, generate_audio)
        model_availability[ModelTier.FAST] = True
        logger.info("Kokoro model loaded successfully!")
        return True
    except ImportError as e:
        # mlx-audio not installed or has dependency conflicts
        logger.info(f"Fast tier unavailable: mlx-audio not compatible with current environment")
        logger.debug(f"Import error: {e}")
        model_availability[ModelTier.FAST] = False
        return False
    except Exception as e:
        logger.warning(f"Fast tier unavailable: {e}")
        model_availability[ModelTier.FAST] = False
        return False


def load_chatterbox_turbo():
    """Load Chatterbox Turbo model (Normal tier)"""
    global models, model_availability, current_device

    if not TORCH_AVAILABLE:
        logger.warning("PyTorch not available, skipping Turbo model")
        return False

    logger.info("Loading Chatterbox Turbo model (Normal tier, 350M)...")
    try:
        from chatterbox.tts_turbo import ChatterboxTurboTTS
        models[ModelTier.NORMAL] = ChatterboxTurboTTS.from_pretrained(device=current_device)
        model_availability[ModelTier.NORMAL] = True
        logger.info("Chatterbox Turbo model loaded successfully!")
        return True
    except Exception as e:
        logger.error(f"Failed to load Turbo model: {e}")
        model_availability[ModelTier.NORMAL] = False
        return False


def load_chatterbox_standard():
    """Load Chatterbox Standard model (High Quality tier)"""
    global models, model_availability, current_device

    if not TORCH_AVAILABLE:
        logger.warning("PyTorch not available, skipping Standard model")
        return False

    logger.info("Loading Chatterbox Standard model (High Quality tier, 500M)...")
    try:
        from chatterbox.tts import ChatterboxTTS
        models[ModelTier.HIGH_QUALITY] = ChatterboxTTS.from_pretrained(device=current_device)
        model_availability[ModelTier.HIGH_QUALITY] = True
        logger.info("Chatterbox Standard model loaded successfully!")
        return True
    except Exception as e:
        logger.error(f"Failed to load Standard model: {e}")
        model_availability[ModelTier.HIGH_QUALITY] = False
        return False


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load models and voice library on startup, cleanup on shutdown"""
    global models, current_device, model_availability

    # Load voice library first
    logger.info("Loading voice library...")
    load_voice_library()

    # Determine device for PyTorch models
    if TORCH_AVAILABLE:
        if torch.backends.mps.is_available():
            current_device = "mps"
        elif torch.cuda.is_available():
            current_device = "cuda"
        else:
            current_device = "cpu"
    else:
        current_device = "mlx"  # MLX-only mode

    logger.info(f"Using device: {current_device}")

    # Load Fast tier (Kokoro - always load, it's required)
    load_kokoro_model()

    # Load Normal tier (Chatterbox Turbo) if available
    load_chatterbox_turbo()

    # Load High Quality tier (Chatterbox Standard) if available
    load_chatterbox_standard()

    # Log summary
    loaded_tiers = [tier.value for tier, loaded in model_availability.items() if loaded]
    logger.info(f"Loaded tiers: {loaded_tiers}")

    yield

    # Cleanup
    logger.info("Shutting down TTS server...")
    models[ModelTier.FAST] = None
    models[ModelTier.NORMAL] = None
    models[ModelTier.HIGH_QUALITY] = None


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
    # New tier-based status
    tiers_status = {
        "fast": TierStatus(
            available=model_availability[ModelTier.FAST],
            loaded=models[ModelTier.FAST] is not None
        ),
        "normal": TierStatus(
            available=model_availability[ModelTier.NORMAL],
            loaded=models[ModelTier.NORMAL] is not None
        ),
        "high": TierStatus(
            available=model_availability[ModelTier.HIGH_QUALITY],
            loaded=models[ModelTier.HIGH_QUALITY] is not None
        ),
    }

    # Legacy format for backwards compatibility
    models_status = {
        "standard": models[ModelTier.HIGH_QUALITY] is not None,
        "turbo": models[ModelTier.NORMAL] is not None,
        "kokoro": models[ModelTier.FAST] is not None,
    }

    # Server is OK if at least one model is loaded
    any_loaded = any(m is not None for m in models.values())
    available = []
    if models[ModelTier.FAST] is not None:
        available.append("fast")
    if models[ModelTier.NORMAL] is not None:
        available.append("normal")
    if models[ModelTier.HIGH_QUALITY] is not None:
        available.append("high")

    return HealthResponse(
        status="ok" if any_loaded else "no_models_loaded",
        tiers=tiers_status,
        device=current_device,
        models_loaded=models_status,
        available_models=available
    )


def generate_kokoro(text: str, voice: str = "af_bella", speed: float = 1.0) -> tuple[np.ndarray, int]:
    """Generate audio using Kokoro (Fast tier)"""
    kokoro_data = models[ModelTier.FAST]
    if kokoro_data is None:
        raise HTTPException(status_code=503, detail="Kokoro model not loaded")

    kokoro_model, generate_audio_fn = kokoro_data

    # Validate voice
    if voice not in KOKORO_VOICES and voice != "default":
        logger.warning(f"Unknown Kokoro voice '{voice}', using af_bella")
        voice = "af_bella"
    elif voice == "default":
        voice = "af_bella"

    logger.info(f"Generating with Kokoro: voice={voice}, text='{text[:50]}...'")

    # Generate audio using mlx-audio API
    audio = generate_audio_fn(
        model=kokoro_model,
        text=text,
        voice=voice,
        speed=speed
    )

    # Handle MLX array conversion
    if hasattr(audio, 'tolist'):
        audio_np = np.array(audio.tolist(), dtype=np.float32)
    elif hasattr(audio, 'numpy'):
        audio_np = audio.numpy()
    else:
        audio_np = np.array(audio, dtype=np.float32)

    # Ensure 1D
    if audio_np.ndim > 1:
        audio_np = audio_np.squeeze()

    return audio_np, KOKORO_SAMPLE_RATE


def generate_chatterbox_turbo(text: str, audio_prompt_path: Optional[str] = None) -> tuple[np.ndarray, int]:
    """Generate audio using Chatterbox Turbo (Normal tier)"""
    model = models[ModelTier.NORMAL]
    if model is None:
        raise HTTPException(status_code=503, detail="Chatterbox Turbo model not loaded")

    logger.info(f"Generating with Chatterbox Turbo: text='{text[:50]}...'")

    # Generate
    if audio_prompt_path:
        try:
            wav = model.generate(text=text, audio_prompt_path=audio_prompt_path)
        except Exception as e:
            error_str = str(e)
            if "5 seconds" in error_str or "longer than" in error_str:
                logger.warning(f"Voice sample too short for Turbo, using default: {e}")
                wav = model.generate(text=text)
            else:
                raise
    else:
        wav = model.generate(text=text)

    # Convert to numpy
    if hasattr(wav, 'cpu'):
        audio_np = wav.cpu().numpy()
    else:
        audio_np = np.array(wav)

    if audio_np.ndim > 1:
        audio_np = audio_np.squeeze()

    return audio_np, SAMPLE_RATE


def generate_chatterbox_standard(
    text: str,
    exaggeration: float = 0.5,
    cfg_weight: float = 0.5,
    audio_prompt_path: Optional[str] = None
) -> tuple[np.ndarray, int]:
    """Generate audio using Chatterbox Standard (High Quality tier)"""
    model = models[ModelTier.HIGH_QUALITY]
    if model is None:
        raise HTTPException(status_code=503, detail="Chatterbox Standard model not loaded")

    logger.info(f"Generating with Chatterbox Standard: text='{text[:50]}...', "
                f"exaggeration={exaggeration}, cfg_weight={cfg_weight}")

    wav = model.generate(
        text=text,
        exaggeration=exaggeration,
        cfg_weight=cfg_weight,
        audio_prompt_path=audio_prompt_path
    )

    # Convert to numpy
    if hasattr(wav, 'cpu'):
        audio_np = wav.cpu().numpy()
    else:
        audio_np = np.array(wav)

    if audio_np.ndim > 1:
        audio_np = audio_np.squeeze()

    return audio_np, SAMPLE_RATE


def resolve_tier(request: TTSRequest) -> ModelTier:
    """Resolve the tier to use, handling legacy model parameter and fallbacks"""
    # Handle legacy model parameter
    if request.model is not None:
        if request.model == ModelType.STANDARD:
            return ModelTier.HIGH_QUALITY
        elif request.model == ModelType.TURBO:
            return ModelTier.NORMAL

    tier = request.tier

    # Check if requested tier is available, otherwise fallback
    if models[tier] is None:
        # Try fallback order: fast -> normal -> high
        for fallback in [ModelTier.FAST, ModelTier.NORMAL, ModelTier.HIGH_QUALITY]:
            if models[fallback] is not None:
                logger.warning(f"Tier '{tier.value}' not available, falling back to '{fallback.value}'")
                return fallback
        raise HTTPException(status_code=503, detail="No TTS models loaded")

    return tier


@app.post("/generate", response_model=TTSResponse)
async def generate_speech(request: TTSRequest):
    """Generate speech from text using the specified quality tier"""
    import gc

    # Resolve which tier to use
    tier = resolve_tier(request)
    tier_name = tier.value

    try:
        # Determine voice/audio prompt for Chatterbox models
        audio_prompt_path = request.audio_prompt_path
        if request.voice_id and request.voice_id != "default" and not audio_prompt_path:
            # For Chatterbox tiers, look up voice sample path
            if tier in [ModelTier.NORMAL, ModelTier.HIGH_QUALITY]:
                audio_prompt_path = get_voice_audio_path(request.voice_id)
                if audio_prompt_path:
                    logger.info(f"Using voice sample: {audio_prompt_path}")

        # Clear GPU memory before generation (for PyTorch models)
        if TORCH_AVAILABLE and tier in [ModelTier.NORMAL, ModelTier.HIGH_QUALITY]:
            gc.collect()
            if torch.backends.mps.is_available():
                torch.mps.empty_cache()
                torch.mps.synchronize()

        # Generate based on tier
        try:
            if tier == ModelTier.FAST:
                # Kokoro: use voice_id as Kokoro voice name
                kokoro_voice = request.voice_id if request.voice_id in KOKORO_VOICES else "af_bella"
                audio_np, sample_rate = generate_kokoro(request.text, kokoro_voice, request.speed)
                model_name = "kokoro"

            elif tier == ModelTier.NORMAL:
                audio_np, sample_rate = generate_chatterbox_turbo(request.text, audio_prompt_path)
                model_name = "turbo"

            elif tier == ModelTier.HIGH_QUALITY:
                audio_np, sample_rate = generate_chatterbox_standard(
                    request.text,
                    request.exaggeration,
                    request.cfg_weight,
                    audio_prompt_path
                )
                model_name = "standard"

            else:
                raise HTTPException(status_code=400, detail=f"Unknown tier: {tier}")

        except RuntimeError as e:
            error_msg = str(e).lower()
            if "mps" in error_msg or "memory" in error_msg or "out of memory" in error_msg:
                logger.error(f"GPU memory error: {e}")
                if TORCH_AVAILABLE and torch.backends.mps.is_available():
                    torch.mps.empty_cache()
                raise HTTPException(status_code=503, detail="GPU memory exhausted. Try shorter text.")
            raise

        # Apply speed change for non-Kokoro (Kokoro handles speed internally)
        output_sample_rate = sample_rate
        if tier != ModelTier.FAST and request.speed != 1.0:
            audio_np, output_sample_rate = apply_speed_change(audio_np, request.speed, sample_rate)

        # Calculate duration
        duration = len(audio_np) / output_sample_rate

        # Convert to WAV bytes
        buffer = io.BytesIO()
        sf.write(buffer, audio_np, output_sample_rate, format='WAV')
        buffer.seek(0)

        # Encode to base64
        audio_base64 = base64.b64encode(buffer.read()).decode('utf-8')

        # Clear GPU memory after generation
        if TORCH_AVAILABLE and tier in [ModelTier.NORMAL, ModelTier.HIGH_QUALITY]:
            gc.collect()
            if torch.backends.mps.is_available():
                torch.mps.empty_cache()
                torch.mps.synchronize()

        logger.info(f"Generated {duration:.2f}s of audio using {tier_name} tier ({model_name})")

        return TTSResponse(
            audio_base64=audio_base64,
            sample_rate=output_sample_rate,
            duration_seconds=duration,
            format="wav",
            tier_used=tier_name,
            model_used=model_name
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Generation failed: {e}", exc_info=True)
        if TORCH_AVAILABLE and torch.backends.mps.is_available():
            torch.mps.empty_cache()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/voices")
async def list_voices(tier: Optional[str] = None):
    """List available voice presets, optionally filtered by tier"""
    result = {
        "kokoro_voices": [],      # Fast tier voices
        "chatterbox_voices": [],  # Normal/High tier voices
        "supports_cloning": True,
        "voice_samples_path": str(VOICE_SAMPLES_DIR)
    }

    # Kokoro voices (Fast tier)
    for voice_id, voice_name in KOKORO_VOICES.items():
        # Parse gender from voice_id pattern (af_*, am_*, bf_*, bm_*)
        gender = "female" if voice_id[1] == "f" else "male"
        accent = "US" if voice_id[0] == "a" else "UK"

        result["kokoro_voices"].append({
            "id": voice_id,
            "name": voice_name,
            "description": f"{accent} accent, {gender}",
            "gender": gender,
            "accent": accent,
            "tier": "fast"
        })

    # Chatterbox voices (Normal/High tiers)
    for voice_id, voice_data in voice_library.items():
        result["chatterbox_voices"].append({
            "id": voice_id,
            "name": voice_data.get("name", voice_id),
            "description": voice_data.get("description", ""),
            "gender": voice_data.get("gender", "unknown"),
            "style": voice_data.get("style", "general"),
            "has_sample": get_voice_audio_path(voice_id) is not None,
            "tier": "normal,high"
        })

    # Add default options
    result["kokoro_voices"].insert(0, {
        "id": "af_bella",
        "name": "Default (Bella)",
        "description": "Default Kokoro voice",
        "gender": "female",
        "accent": "US",
        "tier": "fast",
        "is_default": True
    })

    result["chatterbox_voices"].insert(0, {
        "id": "default",
        "name": "Default",
        "description": "Default Chatterbox voice (no cloning)",
        "gender": "neutral",
        "style": "default",
        "has_sample": False,
        "tier": "normal,high",
        "is_default": True
    })

    # Filter by tier if specified
    if tier == "fast":
        return {"voices": result["kokoro_voices"], **{k: v for k, v in result.items() if k != "chatterbox_voices"}}
    elif tier in ["normal", "high"]:
        return {"voices": result["chatterbox_voices"], **{k: v for k, v in result.items() if k != "kokoro_voices"}}

    # Return all voices with legacy format for backwards compatibility
    return {
        **result,
        "voices": result["chatterbox_voices"]  # Legacy: return Chatterbox as default
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
        log_level="info",
        timeout_keep_alive=300,  # 5 minutes keep-alive timeout
    )
