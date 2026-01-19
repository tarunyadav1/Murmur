#!/bin/bash

# Murmur App Bundle Signing Script
# Recursively signs the app bundle and its components (especially Python)
# to ensure Hardened Runtime compliance for notarization.

set -e

APP_PATH="$1"
IDENTITY="$2" # "Developer ID Application: Your Team (ID)" or "-" for ad-hoc
ENTITLEMENTS="$3"

if [ -z "$APP_PATH" ] || [ -z "$IDENTITY" ] || [ -z "$ENTITLEMENTS" ]; then
    echo "Usage: $0 /path/to/Murmur.app 'DeepMind (TEAM_ID)' /path/to/Murmur.entitlements"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

echo "============================================"
echo "  Recursive Signing: $APP_PATH"
echo "  Identity: $IDENTITY"
echo "============================================"

# Fix ESpeakNG framework structure (remove duplicate bundle at root level)
ESPEAK_FW="$APP_PATH/Contents/Frameworks/ESpeakNG.framework"
if [ -d "$ESPEAK_FW/espeak-ng-data.bundle" ] && [ ! -L "$ESPEAK_FW/espeak-ng-data.bundle" ]; then
    echo "Fixing ESpeakNG framework structure..."
    rm -rf "$ESPEAK_FW/espeak-ng-data.bundle"
fi

# Sign all helper binaries, .so files, and .dylib files first (inside-out)
echo "Finding and signing libraries and executables..."

# 1. Target all .so, .dylib, and binaries in the Python environment
find "$APP_PATH" -type f \( -name "*.so" -o -name "*.dylib" -o -name "python3.11" -o -name "pip" \) | while read -r item; do
    echo "  Signing: $(basename "$item")"
    if [[ "$item" == *"python3.11" ]] || [[ "$item" == *"pip" ]]; then
        /usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" --timestamp "$item"
    else
        /usr/bin/codesign --force --options runtime --sign "$IDENTITY" --timestamp "$item"
    fi
done

# 2. Sign frameworks (inside-out: sign the versioned folder first)
echo "Signing frameworks..."
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    find "$APP_PATH/Contents/Frameworks" -name "*.framework" | while read -r fw; do
        # Sign the actual versioned binary inside the framework
        if [ -d "$fw/Versions/A" ]; then
            # Sign the binary executable inside the framework
            FW_NAME=$(basename "$fw" .framework)
            FW_BINARY="$fw/Versions/A/$FW_NAME"
            if [ -f "$FW_BINARY" ]; then
                echo "  Signing: $FW_NAME binary"
                /usr/bin/codesign --force --options runtime --sign "$IDENTITY" --timestamp "$FW_BINARY"
            fi
            # Sign the versioned folder
            echo "  Signing: $FW_NAME framework (Versions/A)"
            /usr/bin/codesign --force --options runtime --sign "$IDENTITY" --timestamp "$fw/Versions/A"
        fi
        # Finally sign the framework itself
        echo "  Signing: $(basename "$fw")"
        /usr/bin/codesign --force --options runtime --sign "$IDENTITY" --timestamp "$fw"
    done
fi

# 3. Sign the main app bundle last
echo "Signing main application bundle..."
/usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" --timestamp "$APP_PATH"

echo ""
echo "Verifying signature..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Signing complete!"
echo "============================================"
