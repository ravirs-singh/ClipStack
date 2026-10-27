#!/bin/bash
# One-click install for ClipStack.
#   curl -fsSL https://raw.githubusercontent.com/halvent/clipstack/main/install.sh | bash
# Prefers the latest signed DMG from GitHub Releases; falls back to building from source (needs Command Line Tools).
set -euo pipefail
REPO="${CLIPSTACK_REPO:-halvent/clipstack}"
APP="/Applications/ClipStack.app"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }

[ "$(uname)" = "Darwin" ] || { echo "ClipStack is a macOS app."; exit 1; }

asset_url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
  | grep -o '"browser_download_url": *"[^"]*\.\(dmg\|zip\)"' | head -1 | sed 's/.*"\(http[^"]*\)"/\1/' || true)"

if [ -n "$asset_url" ]; then
  say "Downloading $(basename "$asset_url")"
  curl -fL --progress-bar "$asset_url" -o "$TMP/asset"
  say "Installing to /Applications"
  pgrep -xq ClipStack && killall ClipStack && sleep 0.5 || true
  rm -rf "$APP"
  case "$asset_url" in
    *.dmg) mnt="$(hdiutil attach "$TMP/asset" -nobrowse -quiet | grep -o '/Volumes/.*' | head -1)"; cp -R "$mnt/ClipStack.app" "$APP"; hdiutil detach "$mnt" -quiet ;;
    *.zip) ditto -x -k "$TMP/asset" "$TMP/unzipped"; cp -R "$(find "$TMP/unzipped" -maxdepth 2 -name ClipStack.app | head -1)" "$APP" ;;
  esac
  # Unsigned builds carry the quarantine flag; clear it so Gatekeeper doesn't refuse to open the app.
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
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
