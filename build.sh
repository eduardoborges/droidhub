#!/bin/sh
# Builds build/DroidHub.app. The scrcpy server version must match the protocol in Mirror.swift.
set -e
cd "$(dirname "$0")"
SCRCPY=4.1
JAR=".build/scrcpy-server-v$SCRCPY"
[ -f "$JAR" ] || curl -fsSL -o "$JAR" "https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY/scrcpy-server-v$SCRCPY"

swift build -c release
APP=build/DroidHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DroidHub "$APP/Contents/MacOS/"
cp "$JAR" "$APP/Contents/Resources/scrcpy-server"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DroidHub</string>
    <key>CFBundleIdentifier</key><string>com.eduardo.droidhub</string>
    <key>CFBundleName</key><string>DroidHub</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>ScrcpyVersion</key><string>$SCRCPY</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "$APP"
