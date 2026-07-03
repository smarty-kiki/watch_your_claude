#!/bin/bash
# Build a proper .app bundle for WatchYourClaude

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/debug"
APP_DIR="$PROJECT_DIR/WatchYourClaude.app"

echo "Building..."
cd "$PROJECT_DIR"
swift build

# Clean old app
rm -rf "$APP_DIR"

# Create .app structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/WatchYourClaude" "$APP_DIR/Contents/MacOS/WatchYourClaude"

# Copy resources
cp "$PROJECT_DIR/Sources/WatchYourClaude/Resources/notification.wav" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/Sources/WatchYourClaude/Resources/icon.png" "$APP_DIR/Contents/Resources/"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WatchYourClaude</string>
    <key>CFBundleIdentifier</key>
    <string>smarty.watchyourclaude</string>
    <key>CFBundleName</key>
    <string>WatchYourClaude</string>
    <key>CFBundleDisplayName</key>
    <string>WatchYourClaude</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>icon.icns</string>
</dict>
</plist>
PLIST

# Convert PNG to icns
sips -z 512 512 "$APP_DIR/Contents/Resources/icon.png" --out "$APP_DIR/Contents/Resources/icon_512.png" > /dev/null 2>&1
cp "$PROJECT_DIR/icon.icns" "$APP_DIR/Contents/Resources/icon.icns"

echo "Done! App at: $APP_DIR"
echo "Open with: open $APP_DIR"
