#!/bin/bash
set -e

APP_NAME="ExternalDiskTempMonitor"
APP_DIR="${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp Info.plist "$APP_DIR/Contents/"

echo "Compiling..."
swiftc -O -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework DiskArbitration \
    main.swift

echo "Build complete: $SCRIPT_DIR/$APP_DIR"