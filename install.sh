#!/bin/bash
set -e

APP_NAME="ExternalDiskTempMonitor"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/Applications"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.externaldisktempmonitor.plist"

# Build first
bash "$SCRIPT_DIR/build.sh"

# Stop existing OLD instance if running
launchctl unload "$LAUNCH_AGENT_DIR/com.user.disktempmonitor.plist" 2>/dev/null || true
killall "DiskTempMonitor" 2>/dev/null || true
rm -f "$LAUNCH_AGENT_DIR/com.user.disktempmonitor.plist"
rm -rf "$INSTALL_DIR/DiskTempMonitor.app"

# Stop existing instance if running
launchctl unload "$LAUNCH_AGENT_DIR/$PLIST_NAME" 2>/dev/null || true
killall "$APP_NAME" 2>/dev/null || true
sleep 1

# Install app
cp -r "$SCRIPT_DIR/${APP_NAME}.app" "$INSTALL_DIR/"
echo "Installed to $INSTALL_DIR/${APP_NAME}.app"

# Create LaunchAgent for auto-start on login
mkdir -p "$LAUNCH_AGENT_DIR"
cat > "$LAUNCH_AGENT_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.externaldisktempmonitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl load "$LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "LaunchAgent installed. App will auto-start on login."
echo "Starting now..."
open "$INSTALL_DIR/${APP_NAME}.app"
echo "Done!"