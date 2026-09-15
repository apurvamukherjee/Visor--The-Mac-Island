#!/usr/bin/env bash
# Local-only .dmg. Ad-hoc signed, so macOS quarantines it on any other Mac —
# see docs/RESEARCH.md §0 Distribution. Not for sharing, not for the store.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="build/dmg"
STAGE="$BUILD_DIR/stage"
DMG="dist/Visor.dmg"

# The .xcodeproj is generated, not tracked, so a clean checkout has none.
command -v xcodegen >/dev/null || { echo "xcodegen not installed: brew install xcodegen" >&2; exit 1; }
xcodegen generate

xcodebuild -scheme Visor -configuration Release -derivedDataPath "$BUILD_DIR/dd" build

APP="$BUILD_DIR/dd/Build/Products/Release/Visor.app"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname Visor -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
