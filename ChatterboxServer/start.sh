#!/bin/bash
# Start Chatterbox TTS Server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Check if venv exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Virtual environment not found. Running setup first..."
    bash "$SCRIPT_DIR/setup.sh"
fi

# Activate and run
source "$VENV_DIR/bin/activate"
cd "$SCRIPT_DIR"

echo "Starting Chatterbox TTS Server on http://127.0.0.1:8787"
python server.py
