#!/bin/bash

# Murmur App Packaging Script
# Creates a distributable DMG that users can easily download and install
#
# Usage: ./package.sh [--skip-notarize]
#
# Prerequisites:
#   - Xcode command line tools
#   - Valid Apple Developer certificate
#   - For notarization: APPLE_ID, TEAM_ID env vars set

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Murmur.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_NAME="Murmur"
DMG_NAME="Murmur"
SKIP_NOTARIZE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
    esac
done

echo "============================================"
echo "  Murmur Packaging Script"
echo "============================================"
echo ""

# Clean previous builds
echo "[1/6] Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build and archive
echo "[2/6] Building and archiving..."
xcodebuild -project "$PROJECT_DIR/Murmur.xcodeproj" \
    -scheme "Murmur" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    CODE_SIGN_STYLE=Automatic \
    | grep -E "^(Build|Archive|error:|warning:)" || true

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "Error: Archive failed. Check Xcode signing configuration."
    exit 1
fi

echo "Archive created: $ARCHIVE_PATH"

# Export the app
echo "[3/6] Exporting application..."

# Create export options plist
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    | grep -E "^(Export|error:|warning:)" || true

APP_PATH="$EXPORT_PATH/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Export failed."
    exit 1
fi

echo "App exported: $APP_PATH"

# Notarize (optional but recommended for distribution)
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "[4/6] Notarizing application..."

    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ]; then
        echo "  Skipping notarization (APPLE_ID and TEAM_ID not set)"
        echo ""
        echo "  To enable notarization, set these environment variables:"
        echo "    export APPLE_ID='your@email.com'"
        echo "    export TEAM_ID='YOUR_TEAM_ID'"
        echo ""
        echo "  And store credentials:"
        echo "    xcrun notarytool store-credentials 'AC_PASSWORD' \\"
        echo "      --apple-id \$APPLE_ID --team-id \$TEAM_ID"
        echo ""
    else
        # Create zip for notarization
        ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
        ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

        echo "  Submitting to Apple for notarization..."
        xcrun notarytool submit "$ZIP_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --keychain-profile "AC_PASSWORD" \
            --wait

        echo "  Stapling notarization ticket..."
        xcrun stapler staple "$APP_PATH"

        rm "$ZIP_PATH"
        echo "  Notarization complete!"
    fi
else
    echo "[4/6] Skipping notarization (--skip-notarize flag)"
fi

# Create DMG
echo "[5/6] Creating DMG installer..."

DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
DMG_TEMP="$BUILD_DIR/dmg_temp"

# Create temporary directory for DMG contents
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$DMG_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Cleanup temp directory
rm -rf "$DMG_TEMP"

echo "DMG created: $DMG_PATH"

# Create ZIP as alternative
echo "[6/6] Creating ZIP archive..."
ZIP_DIST_PATH="$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_DIST_PATH"
echo "ZIP created: $ZIP_DIST_PATH"

# Verify bundle contents
echo "Verifying bundle contents..."
if [ -d "$APP_PATH/Contents/Resources/ChatterboxServer" ]; then
    echo "  ChatterboxServer: OK"
else
    echo "  WARNING: ChatterboxServer not found in bundle!"
fi

if [ -d "$APP_PATH/Contents/Resources/VoiceSamples" ]; then
    echo "  VoiceSamples: OK"
else
    echo "  WARNING: VoiceSamples not found in bundle!"
fi

# Summary
echo ""
echo "============================================"
echo "  Packaging Complete!"
echo "============================================"
echo ""
echo "Distributable files created in: $BUILD_DIR"
echo ""
echo "  - $DMG_NAME.dmg  (Recommended for sharing)"
echo "  - $APP_NAME.zip  (Alternative)"
echo ""
echo "Requirements for users:"
echo "  - macOS 14.0 or later"
echo "  - Internet connection for first launch"
echo ""
echo "First launch experience:"
echo "  1. User downloads and installs Murmur"
echo "  2. On first launch, app automatically sets up (takes a few minutes)"
echo "  3. Ready to use!"
echo ""

# Show file sizes
echo "File sizes:"
ls -lh "$DMG_PATH" "$ZIP_DIST_PATH" 2>/dev/null | awk '{print "  " $9 ": " $5}'
echo ""
