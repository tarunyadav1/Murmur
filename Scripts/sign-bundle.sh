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

# 2. Target any other frameworks or helpers (if any)
# find "$APP_PATH/Contents/Frameworks" -name "*.framework" -exec codesign --force --options runtime --sign "$IDENTITY" --timestamp {} \; 2>/dev/null || true

# 3. Sign the main app bundle last
echo "Signing main application bundle..."
/usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" --timestamp "$APP_PATH"

echo ""
echo "Verifying signature..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Signing complete!"
echo "============================================"
