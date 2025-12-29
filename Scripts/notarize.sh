#!/bin/bash

# Murmur App Notarization Script
# Usage: ./notarize.sh /path/to/Murmur.app

set -e

APP_PATH="$1"
BUNDLE_ID="com.murmur.app"

# These should be set in your environment or keychain
# APPLE_ID="your@email.com"
# TEAM_ID="YOUR_TEAM_ID"
# APP_PASSWORD stored in keychain as "AC_PASSWORD"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/Murmur.app"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

echo "=== Murmur Notarization Script ==="
echo "App: $APP_PATH"
echo ""

# Step 1: Create ZIP for notarization
echo "Creating ZIP archive..."
ZIP_PATH="${APP_PATH%.*}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created: $ZIP_PATH"
echo ""

# Step 2: Submit for notarization
echo "Submitting for notarization..."
echo "(This may take several minutes)"
echo ""

if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ]; then
    echo "Error: APPLE_ID and TEAM_ID environment variables must be set"
    echo ""
    echo "Set them like this:"
    echo "  export APPLE_ID='your@email.com'"
    echo "  export TEAM_ID='YOUR_TEAM_ID'"
    echo ""
    echo "And store your app-specific password in keychain:"
    echo "  xcrun notarytool store-credentials 'AC_PASSWORD' \\"
    echo "    --apple-id \$APPLE_ID \\"
    echo "    --team-id \$TEAM_ID \\"
    echo "    --password 'your-app-specific-password'"
    exit 1
fi

xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --keychain-profile "AC_PASSWORD" \
    --wait

# Step 3: Staple the ticket
echo ""
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# Cleanup
rm "$ZIP_PATH"

echo ""
echo "=== Notarization Complete ==="
echo "Your app is ready for distribution!"
echo ""
echo "To create a DMG:"
echo "  hdiutil create -volname 'Murmur' -srcfolder '$APP_PATH' -ov 'Murmur.dmg'"
