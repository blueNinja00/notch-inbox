#!/bin/bash
# Builds "Notch Inbox.app" (menu-bar only, no Dock icon) into ./build
# BUILD_NUMBER (set by the GitHub release workflow) is what the updater compares.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${BUILD_NUMBER:-0}"

echo "Building… (the first build takes a minute or two)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Notch Inbox.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchInbox" "$APP/Contents/MacOS/NotchInbox"
# The Gmail browser add-on ships inside the app; "Set Up Browser Link…" installs it.
cp -R BrowserExtension "$APP/Contents/Resources/BrowserExtension"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Notch Inbox</string>
    <key>CFBundleDisplayName</key>
    <string>Notch Inbox</string>
    <key>CFBundleIdentifier</key>
    <string>local.notchinbox</string>
    <key>CFBundleExecutable</key>
    <string>NotchInbox</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.${BUILD_NUMBER}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will launch the app.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "Done: $APP (build $BUILD_NUMBER)"
echo "Start it with:  open \"$APP\""
