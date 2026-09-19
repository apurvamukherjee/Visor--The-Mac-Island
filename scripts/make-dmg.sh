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
[ -n "$VERSION" ] || VERSION="0.0.0"
# Semantic versioning, MAJOR.MINOR.PATCH, enforced here rather than trusted:
# the filename is the permanent record, and a "1.6" that should have been
# "1.6.0" cannot be corrected later without rewriting history.
case "$VERSION" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *)
        echo "MARKETING_VERSION must be MAJOR.MINOR.PATCH (got \"$VERSION\")" >&2
        exit 1
        ;;
esac
BUILD="$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\(.*\)".*/\1/p' project.yml)"
[ -n "$BUILD" ] || BUILD="1"
# Seconds, not just the date: several builds a day is the normal case, and the
# old -2/-3 suffix said which was later but not when either was cut. Seconds
# rather than minutes because two builds of one commit inside the same minute
# would otherwise resolve to the same permanent path.
STAMP="$(date +%Y-%m-%d-%H%M%S)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
mkdir -p "$RELEASES"
RELEASE="$RELEASES/Visor-$VERSION-build$BUILD-$STAMP-$COMMIT.dmg"
# These are permanent, and a release that is already on disk is history:
# refuse rather than overwrite it.
if [ -e "$RELEASE" ]; then
    echo "release already exists: $RELEASE" >&2
    exit 1
fi
cp "$DMG" "$RELEASE"

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "release copy: $RELEASE"
echo
echo "ad-hoc signed: on any other Mac, run"
echo "  xattr -dr com.apple.quarantine /Applications/Visor.app"
