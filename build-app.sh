#!/bin/bash
# Builds ClipStack.app (release) into ./dist
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=dist/ClipStack.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClipStack "$APP/Contents/MacOS/ClipStack"
cp Info.plist "$APP/Contents/Info.plist"
# Ad-hoc sign so Accessibility permission sticks across rebuilds.
codesign --force --deep --sign - "$APP"
echo "Built $APP — open it with: open $APP"
