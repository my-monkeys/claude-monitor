#!/bin/bash
# Build and install ClaudeMonitor.app into /Applications
set -e

cd "$(dirname "$0")"

echo "Building..."
swift build -c release 2>&1 | tail -3

APP="/Applications/ClaudeMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/ClaudeMonitor "$APP/Contents/MacOS/"

# Copy bundled resources (SPM resource bundle — next to executable for Bundle.module)
BUNDLE_RES=$(find .build -name "ClaudeMonitor_ClaudeMonitor.bundle" -type d 2>/dev/null | head -1)
if [ -n "$BUNDLE_RES" ]; then
  cp -R "$BUNDLE_RES" "$APP/Contents/MacOS/"
  cp -R "$BUNDLE_RES" "$APP/Contents/Resources/"
  echo "  Resources bundled"
fi

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>fr.my-monkey.claude-monitor</string>
    <key>CFBundleName</key>
    <string>Claude Monitor</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

echo "✓ Installed to $APP"
echo "  Launch: open /Applications/ClaudeMonitor.app"
