#!/usr/bin/env bash
# Local-only .dmg. Ad-hoc signed, so macOS quarantines it on any other Mac —
# see docs/RESEARCH.md §0 Distribution. Not for sharing, not for the store.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="build/dmg"
STAGE="$BUILD_DIR/stage"
DMG="dist/Notchy.dmg"

xcodebuild -scheme Notchy -configuration Release -derivedDataPath "$BUILD_DIR/dd" build

APP="$BUILD_DIR/dd/Build/Products/Release/Notchy.app"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname Notchy -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
