#!/bin/bash
# One-click-install release: builds ClipStack.app, signs it with your Developer ID, notarizes with Apple,
# staples the ticket, and packs a drag-to-Applications DMG. Output: dist/ClipStack-<version>.dmg
#
# One-time setup (needs an Apple Developer account, $99/yr):
#   1. Xcode → Settings → Accounts → Manage Certificates → "+" → Developer ID Application
#   2. Create an app-specific password at appleid.apple.com, then store it once:
#        xcrun notarytool store-credentials clipstack-notary --apple-id you@example.com --team-id TEAMID --password app-specific-pw
#   3. export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
#
# Usage: ./release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
SIGN_ID="${SIGN_ID:?set SIGN_ID to your 'Developer ID Application: …' identity}"
PROFILE="${NOTARY_PROFILE:-clipstack-notary}"
APP=dist/ClipStack.app
DMG="dist/ClipStack-$VERSION.dmg"

# Stamp the version into the bundle
sed -i '' "s|<key>CFBundleShortVersionString</key> <string>[^<]*</string>|<key>CFBundleShortVersionString</key> <string>$VERSION</string>|" Info.plist
sed -i '' "s|<key>CFBundleVersion</key>         <string>[^<]*</string>|<key>CFBundleVersion</key>         <string>$(date +%Y%m%d%H%M)</string>|" Info.plist

echo "▸ Building"
swift build -c release
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipStack "$APP/Contents/MacOS/ClipStack"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/menubar.png Assets/menubar@2x.png "$APP/Contents/Resources/" 2>/dev/null || true
iconutil -c icns Assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing with hardened runtime"
codesign --force --deep --options runtime --timestamp --entitlements entitlements.plist --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "▸ Building DMG"
rm -f "$DMG"; rm -rf dist/dmg; mkdir -p dist/dmg
cp -R "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "ClipStack" -srcfolder dist/dmg -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "▸ Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Done: $DMG"
shasum -a 256 "$DMG"
echo "Next: gh release create v$VERSION $DMG --title \"ClipStack $VERSION\" --notes-file CHANGELOG.md"
