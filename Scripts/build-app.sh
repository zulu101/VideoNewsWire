#!/bin/bash
# Baut VideoNewsWire.app (Release, Apple Silicon) nach ./build/
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/VideoNewsWire.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VideoNewsWire" "$APP/Contents/MacOS/VideoNewsWire"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION="${VERSION:-0.1.0}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>VideoNewsWire</string>
    <key>CFBundleDisplayName</key><string>VideoNewsWire</string>
    <key>CFBundleIdentifier</key><string>app.videonewswire.VideoNewsWire</string>
    <key>CFBundleExecutable</key><string>VideoNewsWire</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 zulu101 · MIT-Lizenz</string>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur (für lokale Nutzung ausreichend)
codesign --force --deep --sign - "$APP"

echo "Fertig: $APP"
