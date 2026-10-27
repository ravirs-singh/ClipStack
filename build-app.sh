#!/bin/bash
# Builds ClipStack.app (release) into ./dist and relaunches it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=dist/ClipStack.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClipStack "$APP/Contents/MacOS/ClipStack"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/menubar.png Assets/menubar@2x.png "$APP/Contents/Resources/" 2>/dev/null || true
mkdir -p "$APP/Contents/Resources"
iconutil -c icns Assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc sign so Accessibility permission sticks across rebuilds.
codesign --force --deep --sign - "$APP"

# `open` on an already-running app just activates the old process, so quit it first.
if pgrep -xq ClipStack; then
    killall ClipStack
    sleep 0.5
fi
open "$APP"
echo "Built and launched $APP ($(date '+%b %d %H:%M'))"
