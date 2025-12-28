#!/bin/bash
# Copy TTS resources to app bundle after build

APP_BUNDLE="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources"

# Copy model file
if [ -f "$SRCROOT/kokoro-v1_0.safetensors" ]; then
    cp "$SRCROOT/kokoro-v1_0.safetensors" "$APP_BUNDLE/"
    echo "Copied kokoro model to app bundle"
fi

# Copy voice files from Swift-TTS bundle to main Resources
VOICE_BUNDLE="$APP_BUNDLE/Swift-TTS_Swift-TTS.bundle/Contents/Resources"
if [ -d "$VOICE_BUNDLE" ]; then
    cp "$VOICE_BUNDLE"/*.json "$APP_BUNDLE/"
    echo "Copied voice files to app bundle"
fi
