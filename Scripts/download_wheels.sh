#!/bin/bash
# Download all pip wheels for offline installation
# This script downloads wheels for macOS arm64 (Apple Silicon)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHEELS_DIR="$PROJECT_DIR/Resources/PythonWheels"
REQUIREMENTS_FILE="$PROJECT_DIR/Server/requirements.txt"

# Python version must match bundled Python
PYTHON_VERSION="3.11"

echo "=== Downloading pip wheels for offline installation ==="
echo "Wheels directory: $WHEELS_DIR"
echo "Requirements file: $REQUIREMENTS_FILE"

# Clean and create wheels directory
rm -rf "$WHEELS_DIR"
mkdir -p "$WHEELS_DIR"

# Check for Python 3.11
if command -v python3.11 &> /dev/null; then
    PYTHON_CMD="python3.11"
elif command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    echo "Warning: Using python3 instead of python3.11. Ensure it's version 3.11."
else
    echo "Error: Python 3.11 is required but not found"
    exit 1
fi

echo "Using Python: $($PYTHON_CMD --version)"

# Download wheels for macOS arm64
echo ""
echo "Downloading wheels for macOS arm64..."
$PYTHON_CMD -m pip download \
    --platform macosx_11_0_arm64 \
    --platform macosx_12_0_arm64 \
    --platform macosx_13_0_arm64 \
    --platform macosx_14_0_arm64 \
    --python-version $PYTHON_VERSION \
    --only-binary=:all: \
    --dest "$WHEELS_DIR" \
    -r "$REQUIREMENTS_FILE" 2>&1 || true

# Some packages may not have pre-built wheels, download source distributions as fallback
echo ""
echo "Downloading any missing packages (including source distributions)..."
$PYTHON_CMD -m pip download \
    --dest "$WHEELS_DIR" \
    --platform macosx_11_0_arm64 \
    --platform macosx_12_0_arm64 \
    --platform macosx_13_0_arm64 \
    --platform macosx_14_0_arm64 \
    --python-version $PYTHON_VERSION \
    -r "$REQUIREMENTS_FILE" 2>&1 || true

# Count downloaded files
WHEEL_COUNT=$(find "$WHEELS_DIR" -name "*.whl" | wc -l | tr -d ' ')
TAR_COUNT=$(find "$WHEELS_DIR" -name "*.tar.gz" -o -name "*.zip" | wc -l | tr -d ' ')

echo ""
echo "=== Download complete ==="
echo "Wheels downloaded: $WHEEL_COUNT"
echo "Source distributions: $TAR_COUNT"
echo "Total size: $(du -sh "$WHEELS_DIR" | cut -f1)"
echo ""
echo "Files:"
ls -lh "$WHEELS_DIR"

# Verify we have the critical packages
echo ""
echo "=== Verifying critical packages ==="
CRITICAL_PACKAGES=("mlx" "mlx_audio" "fastapi" "uvicorn" "numpy" "scipy" "soundfile" "misaki" "spacy")
MISSING=()

for pkg in "${CRITICAL_PACKAGES[@]}"; do
    if ls "$WHEELS_DIR"/${pkg}*.whl 1> /dev/null 2>&1 || ls "$WHEELS_DIR"/${pkg}*.tar.gz 1> /dev/null 2>&1; then
        echo "✓ $pkg"
    else
        echo "✗ $pkg (MISSING)"
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "Warning: Some critical packages may be missing. The download may have failed for:"
    printf '%s\n' "${MISSING[@]}"
    echo ""
    echo "You may need to manually download these or check your network connection."
fi

echo ""
echo "Done! Wheels are ready in: $WHEELS_DIR"
