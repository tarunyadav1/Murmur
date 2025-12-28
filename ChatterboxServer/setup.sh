#!/bin/bash
# Setup script for Chatterbox TTS Server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

echo "=== Chatterbox TTS Server Setup ==="

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
echo "Python version: $PYTHON_VERSION"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies..."
pip install -r "$SCRIPT_DIR/requirements.txt"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start the server, run:"
echo "  cd $SCRIPT_DIR"
echo "  source venv/bin/activate"
echo "  python server.py"
echo ""
echo "Or use: ./start.sh"
