#!/bin/bash
set -e

APP_NAME="ExternalDiskTempMonitor"

# Stop existing instance if running
launchctl unload "$HOME/Library/LaunchAgents/com.user.externaldisktempmonitor.plist" 2>/dev/null || true
killall "$APP_NAME" 2>/dev/null || true

echo "Downloading pre-compiled $APP_NAME..."
curl -L https://github.com/BingkangShi/ExternalDiskTempMonitor/releases/latest/download/ExternalDiskTempMonitor.zip -o /tmp/ExternalDiskTempMonitor.zip

echo "Extracting app to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
unzip -q /tmp/ExternalDiskTempMonitor.zip -d /Applications
rm /tmp/ExternalDiskTempMonitor.zip

echo "Configuring auto-start..."
mkdir -p ~/Library/LaunchAgents
cat << 'EOF' > ~/Library/LaunchAgents/com.user.externaldisktempmonitor.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.externaldisktempmonitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/ExternalDiskTempMonitor.app/Contents/MacOS/ExternalDiskTempMonitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.user.externaldisktempmonitor.plist 2>/dev/null || true
open -a ExternalDiskTempMonitor

echo "✅ App installed successfully!"
echo "⚠️ IMPORTANT: Make sure you have installed smartmontools:"
echo "brew install smartmontools"
echo ""
