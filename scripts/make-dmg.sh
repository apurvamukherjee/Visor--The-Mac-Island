#!/usr/bin/env bash
# Local-only .dmg. Ad-hoc signed, so macOS quarantines it on any other Mac —
# see docs/RESEARCH.md §0 Distribution. Not for sharing, not for the store.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="build/dmg"
STAGE="$BUILD_DIR/stage"
DMG="dist/Visor.dmg"
RELEASES="new-releases"

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
# Keep a dated copy in the repo so a build is downloadable straight from
# GitHub. dist/ is gitignored and gets overwritten; this one is permanent.
VERSION="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml)"
[ -n "$VERSION" ] || VERSION="0.0"
STAMP="$(date +%Y-%m-%d)"
mkdir -p "$RELEASES"
RELEASE="$RELEASES/Visor-$VERSION-$STAMP.dmg"
# Never clobber an earlier build from the same day — suffix instead.
if [ -e "$RELEASE" ]; then
    n=2
    while [ -e "$RELEASES/Visor-$VERSION-$STAMP-$n.dmg" ]; do n=$((n + 1)); done
    RELEASE="$RELEASES/Visor-$VERSION-$STAMP-$n.dmg"
fi
cp "$DMG" "$RELEASE"

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "release copy: $RELEASE"
echo
echo "ad-hoc signed: on any other Mac, run"
echo "  xattr -dr com.apple.quarantine /Applications/Visor.app"
