# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Murmur is a macOS text-to-speech application built with SwiftUI that uses the Kokoro TTS model (82M params) via MLX for fast, on-device speech synthesis. The app runs a local Python FastAPI server to handle TTS generation.

## Build & Run Commands

```bash
# Generate Xcode project from project.yml (uses XcodeGen)
xcodegen generate

# Build release version
xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Release build

# Package for distribution (creates DMG and ZIP)
./Scripts/package.sh

# Package without notarization (faster for testing)
./Scripts/package.sh --skip-notarize
```

## Architecture

### Swift App (macOS 14.0+, Swift 5.9)

**Entry Point:** `MurmurApp.swift`
- Manages app lifecycle with license validation → setup → main content flow
- Creates and wires all services as `@StateObject`

**Services (in `Services/`):**
- `PythonEnvironmentService` - Sets up bundled Python venv in `~/Library/Application Support/Murmur/`, installs pip dependencies, copies server files from bundle
- `ServerManager` - Launches/monitors the Kokoro Python server on port 8787, handles auto-restart on crash
- `TTSService` - HTTP client for the Kokoro server, handles audio generation and WAV decoding
- `LicenseService` - Gumroad license validation with 30-day offline grace period
- `AudioPlayerService` - Audio playback using AVFoundation
- `HistoryService` - Persists generation history

**Main UI:**
- `ContentView.swift` - Main interface with text input, voice selection, and floating audio player
- `Views/SetupView.swift` - First-run setup wizard
- `Views/LicenseView.swift` - License activation screen
- `Views/Components/` - Reusable UI components

### Python TTS Server (`Server/kokoro_server.py`)

FastAPI server running on `127.0.0.1:8787`:
- `GET /health` - Server/model status check
- `GET /voices` - List available Kokoro voices
- `POST /generate` - Generate speech (text, voice, speed) → base64 WAV

Uses `mlx-audio` for MLX-accelerated inference on Apple Silicon. Model loads from bundled `Resources/KokoroModel/` or falls back to HuggingFace cache.

## Key Patterns

### Python Environment Setup
The app bundles Python 3.11 in `Resources/Python/` and creates a venv at first launch. Server files and voice samples are copied from the app bundle to Application Support. Version tracking in `.setup_version` triggers rebuild on app updates.

### Server Communication
Swift communicates with Python via HTTP. `ServerManager` spawns the process and monitors health. If server becomes unhealthy, it auto-restarts after 2 consecutive failures.

### Code Signing
Pip-installed packages are re-signed with ad-hoc signatures to avoid Team ID conflicts with the app's signature (`stripCodeSignatures()` in `PythonEnvironmentService`).

## Resource Bundles

Located in `Resources/`:
- `Python/` - Bundled Python 3.11 interpreter
- `KokoroModel/` - Pre-downloaded Kokoro model weights
- `VoiceSamples/` - Voice preview audio files
- `GenshinVoices/`, `Voices/` - Additional voice data

## Important Files

- `project.yml` - XcodeGen project configuration
- `Server/requirements.txt` - Python dependencies for TTS server
- `Utilities/Constants.swift` - App-wide constants including Gumroad product ID
- `Utilities/DesignSystem.swift` - UI styling constants (`MurmurDesign`)
