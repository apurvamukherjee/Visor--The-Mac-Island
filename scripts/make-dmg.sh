#!/usr/bin/env bash
# Local-only .dmg. Ad-hoc signed, so macOS quarantines it on any other Mac —
# see the 2.x RESEARCH.md §0 Distribution (backup/docs/, or git history).
# Not for sharing, not for the store.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="build/dmg"
STAGE="$BUILD_DIR/stage"
DMG="dist/Visor.dmg"
RELEASES="new-releases"
VOLNAME="Visor"

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

# The window dressing: background art with the drag arrow, icon positions, no
# toolbar. Finder only persists this into the volume's .DS_Store if the disk is
# writable and mounted, so the .dmg is built read-write, decorated, detached,
# then converted to the compressed read-only image that actually ships.
# The art lives INSIDE Visor.app, not at the volume root. A root-level
# `.background.tiff` (or a `.background/` folder) is a real entry in the
# window for anyone browsing with AppleShowAllFiles=1, and `chflags hidden`
# does not help them — Finder lists flagged items anyway (verified). Putting
# it in the bundle means the volume ships exactly two visible entries.
# The .DS_Store's `icvp` record stores the background as a Carbon *alias* to a
# real file, so the file cannot simply be deleted before detach: the record
# survives, the alias dangles, and the window paints plain grey (measured).
# One multi-resolution .tiff rather than a 1x/2x pair — macOS reads the Retina
# rep out of the tiff the same way it reads a "@2x" sibling, and `tiffutil` is
# part of macOS, so it adds no dependency.
tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png \
    -out "$STAGE/Visor.app/Contents/Resources/dmg-background.tiff" >/dev/null
# Adding a file after Xcode signed the bundle breaks its resource seal, so
# `codesign --verify` fails on the shipped app until the outer bundle is resealed.
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags "$STAGE/Visor.app"
codesign --verify --deep --strict "$STAGE/Visor.app"

RW="$BUILD_DIR/rw.dmg"
rm -f "$RW" "$DMG"
# Staged under a unique volume name, renamed to $VOLNAME just before detaching.
# Finder's AppleScript addresses a disk by *name*, so if any older Visor image
# is still mounted — and after a few release builds several usually are —
# `tell disk "Visor"` would decorate one of those read-only volumes instead of
# this one, and fail with -10006.
STAGEVOL="Visor-build-$$"
hdiutil create -volname "$STAGEVOL" -srcfolder "$STAGE" -ov -format UDRW \
    -fs HFS+ "$RW" >/dev/null

# Everything after this addresses the volume by *device node*. Older Visor
# images left mounted take the name "Visor", so a path- or name-based detach
# can pick the wrong volume and leave this one attached — which then fails the
# convert with "Resource temporarily unavailable".
ATTACH="$(hdiutil attach "$RW" -noautoopen)"
DEV="$(echo "$ATTACH" | awk '/Apple_HFS/ {print $1; exit}')"
# The mount path comes from the same line, not from /Volumes/$STAGEVOL: if the
# name were ever taken, macOS appends " 1" and the guessed path is wrong.
MOUNTPT="$(echo "$ATTACH" | awk '/Apple_HFS/ {sub(/^[^\t]*\t[^\t]*\t/, ""); print; exit}')"
[ -n "$DEV" ] && [ -d "$MOUNTPT" ] || { echo "could not attach $RW" >&2; exit 1; }
trap 'hdiutil detach "$DEV" -force >/dev/null 2>&1 || true' EXIT

osascript <<APPLESCRIPT >/dev/null || { echo "Finder layout failed" >&2; exit 1; }
tell application "Finder"
    set vol to disk "$STAGEVOL"
    -- Addressed as a POSIX path, never by traversing folder-of-folder into
    -- the bundle: Finder treats a .app as an application, not a folder, and
    -- fails that traversal with -1728. By path it accepts the assignment and
    -- writes a proper icvp alias into the volume .DS_Store (verified).
    set bg to (POSIX file "$MOUNTPT/Visor.app/Contents/Resources/dmg-background.tiff") as alias
    open vol
    set win to container window of vol
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    set the bounds of win to {200, 140, 740, 540}
    set opts to the icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 12
    set label position of opts to bottom
    set background picture of opts to bg
    set position of item "Visor.app" of vol to {145, 170}
    set position of item "Applications" of vol to {395, 170}
    close win
    open vol
    -- Reopening resets the chrome, so hide it again on the fresh window;
    -- what Finder records is the state of the window it last had open.
    set win2 to container window of vol
    set toolbar visible of win2 to false
    set statusbar visible of win2 to false
    set the bounds of win2 to {200, 140, 740, 540}
    update vol without registering applications
    delay 2
    -- Chrome once more, last thing before the close: Finder snapshots the
    -- window state it is closing, and the update above can bring it back.
    set toolbar visible of win2 to false
    set statusbar visible of win2 to false
    set the bounds of win2 to {200, 140, 740, 540}
    delay 1
    close win2
end tell
APPLESCRIPT

# Finder writes .DS_Store asynchronously after the window closes. chflags on a
# file it is still writing loses the layout, so settle first.
sleep 2
sync

# `chflags hidden` is belt-and-braces: the leading dot already hides .DS_Store
# under default Finder settings, and the flag does NOT hide it from anyone who
# has set AppleShowAllFiles (verified — Finder lists flagged items anyway).
# It costs nothing and is what the modern tooling does; `SetFile -a V` is the
# deprecated spelling and silently fails on current macOS. The art is not
# listed here: it lives inside Visor.app, so it is never a window entry.
chflags hidden "$MOUNTPT/.DS_Store" 2>/dev/null || true

# osascript returning 0 does NOT mean Finder wrote the layout: build 23 shipped
# a plain grey window from a successful-looking run. The evidence is the size —
# a .DS_Store carrying the icvp background alias and both icon positions runs
# ~10KB, while the bare record Finder writes for any folder it merely opened is
# 6148 bytes. Measured across builds 16-23. Fail here rather than ship unstyled.
DS_BYTES=$(stat -f %z "$MOUNTPT/.DS_Store" 2>/dev/null || echo 0)
if [ "$DS_BYTES" -lt 8192 ]; then
    echo "Finder layout not recorded: .DS_Store is ${DS_BYTES}B, expected >8192B." >&2
    echo "The window would open unstyled. Re-run; this step races Finder." >&2
    exit 1
fi

# Finder writes .DS_Store lazily; sync so the record is on the image before the
# volume is renamed and detached, otherwise the layout is silently lost.
sync
diskutil rename "$DEV" "$VOLNAME" >/dev/null
# Renaming moves the mount, so the old path is stale from here on.
MOUNTPT="/Volumes/$VOLNAME"

# .fseventsd goes last. macOS maintains it for as long as the volume is mounted
# and writable, so deleting it any earlier just means it is back by the time the
# image is converted — measured, not assumed. Every shipped .dmg inspected
# (Rectangle, IINA) ships without one.
rm -rf "$MOUNTPT/.fseventsd" 2>/dev/null || true
sync

# The volume ships exactly Visor.app, the Applications alias and .DS_Store.
# Asserted rather than trusted: every extra entry so far (.background.tiff,
# .fseventsd, .Trashes) arrived silently and was only found by mounting a
# shipped image by hand. Aborting here costs one build; shipping costs a
# release nobody can delete.
ACTUAL="$(ls -A "$MOUNTPT" | sort | tr '\n' ' ')"
EXPECTED=".DS_Store Applications Visor.app "
if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "DMG volume contents unexpected." >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual:   $ACTUAL" >&2
    exit 1
fi

# One last sweep immediately before detaching. `.fseventsd` is recreated during
# the detach itself — measured on build 29, which shipped one past an assertion
# that had just passed. Dropping a `no_log` file in it is what actually stops
# macOS maintaining the directory; deleting it alone only wins the race until
# the unmount. The post-convert check below is what guarantees the result.
rm -rf "$MOUNTPT/.fseventsd" 2>/dev/null || true
mkdir -p "$MOUNTPT/.fseventsd" 2>/dev/null || true
touch "$MOUNTPT/.fseventsd/no_log" 2>/dev/null || true
sync
rm -rf "$MOUNTPT/.fseventsd" 2>/dev/null || true
sync
hdiutil detach "$DEV" >/dev/null
trap - EXIT

# One more pass on the *unmounted* read-write image before converting.
# Everything above fights macOS for a directory it recreates for as long as
# the volume is mounted — a race the build cannot win, and build 29 shipped
# past an assertion that had just passed. Re-attaching with `noautofsck` and
# no Spotlight, deleting, and detaching immediately gives macOS no window to
# maintain it in: fsevents is seeded on mount, so the shorter the mount, the
# less there is to lose. The converted-image check below is still what
# guarantees the result.
SWEEP="$(hdiutil attach "$RW" -nobrowse -noautoopen | grep -o '/Volumes/.*' | tail -1)"
if [ -n "$SWEEP" ]; then
    rm -rf "$SWEEP/.fseventsd" 2>/dev/null || true
    sync
    hdiutil detach "$SWEEP" >/dev/null 2>&1 || true
fi

hdiutil convert "$RW" -format ULMO -o "$DMG" >/dev/null
rm -f "$RW"

# Assert on the image that actually ships, not on the read-write volume that
# built it. Everything above can pass and still convert an image with an
# .fseventsd in it, which is exactly what happened on build 29.
VERIFY_MNT="$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | tail -1)"
SHIPPED="$(ls -A "$VERIFY_MNT" | sort | tr '\n' ' ')"
hdiutil detach "$VERIFY_MNT" >/dev/null 2>&1 || true
if [ "$SHIPPED" != "$EXPECTED" ]; then
    echo "Converted .dmg contents unexpected." >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual:   $SHIPPED" >&2
    rm -f "$DMG"
    exit 1
fi
# Keep a dated copy in the repo so a build is downloadable straight from
# GitHub. dist/ is gitignored and gets overwritten; this one is permanent.
# Read from the app that was just built, not grepped out of project.yml:
# project.yml had one MARKETING_VERSION per target while the XPC helper
# existed, and grepping it returned both, putting newlines in the permanent
# filename (3.0.0, measured). The bundle is also the truth about what shipped.
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
# Semantic versioning, MAJOR.MINOR.PATCH, enforced here rather than trusted:
# the filename is the permanent record, and a "1.6" that should have been
# "1.6.0" cannot be corrected later without rewriting history.
# An anchored regex, not a glob: the old glob's `*` let "1.2.3.4" through and
# once matched a multi-line value; `$` here is end of string, not of a line.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "MARKETING_VERSION must be MAJOR.MINOR.PATCH (got \"$VERSION\")" >&2
    exit 1
fi
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
case "$BUILD" in
    "" | *[!0-9]*)
        echo "CURRENT_PROJECT_VERSION must be a whole number (got \"$BUILD\")" >&2
        exit 1
        ;;
esac
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
