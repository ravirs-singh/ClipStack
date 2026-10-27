#!/bin/bash
# One-click install for ClipStack.
#   curl -fsSL https://raw.githubusercontent.com/OWNER/ClipStack/main/install.sh | bash
# Prefers the latest signed DMG from GitHub Releases; falls back to building from source (needs Command Line Tools).
set -euo pipefail
REPO="${CLIPSTACK_REPO:-OWNER/ClipStack}"
APP="/Applications/ClipStack.app"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }

[ "$(uname)" = "Darwin" ] || { echo "ClipStack is a macOS app."; exit 1; }

dmg_url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*"\(http[^"]*\)"/\1/' || true)"

if [ -n "$dmg_url" ]; then
  say "Downloading $(basename "$dmg_url")"
  curl -fL --progress-bar "$dmg_url" -o "$TMP/ClipStack.dmg"
  say "Installing to /Applications"
  mnt="$(hdiutil attach "$TMP/ClipStack.dmg" -nobrowse -quiet | grep -o '/Volumes/.*' | head -1)"
  pgrep -xq ClipStack && killall ClipStack && sleep 0.5 || true
  rm -rf "$APP"; cp -R "$mnt/ClipStack.app" "$APP"
  hdiutil detach "$mnt" -quiet
else
  say "No release DMG found for $REPO — building from source"
  xcode-select -p >/dev/null 2>&1 || { say "Installing Command Line Tools (a dialog will open; re-run after it finishes)"; xcode-select --install; exit 1; }
  git clone --depth 1 "https://github.com/$REPO.git" "$TMP/src"
  (cd "$TMP/src" && swift build -c release >/dev/null)
  pgrep -xq ClipStack && killall ClipStack && sleep 0.5 || true
  rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$TMP/src/.build/release/ClipStack" "$APP/Contents/MacOS/ClipStack"
  cp "$TMP/src/Info.plist" "$APP/Contents/Info.plist"
  cp "$TMP/src"/Assets/menubar*.png "$APP/Contents/Resources/"
  iconutil -c icns "$TMP/src/Assets/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
  codesign --force --deep --sign - "$APP"
fi

say "Launching"
open "$APP"
say "Done. ClipStack lives in your menu bar — press ⌘⇧V to open history, or hover the notch."
