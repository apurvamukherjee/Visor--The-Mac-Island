#!/usr/bin/env bash
# Visor — old-code feature port, as a reviewable commit sequence.
#
# Run from the repo root:  bash COMMITS.sh
#
# Each commit is one coherent change. Shared files (NotchStore, IslandLayout,
# Activity) are touched by several features, so they are staged with the
# commit that introduces the property they gained — the sequence is ordered
# so every commit builds on the one before it.
#
# Delete this file afterwards; it is a one-shot, not part of the project.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

A="Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"

# ── 1. Housekeeping ───────────────────────────────────────────────────────
git add .gitignore .swiftformat .swiftlint.yml
git commit -m "chore: exclude GPL reference checkouts from git and linting

old-code/ and DynamicNotch/ are GPL-3.0 clones kept locally to port from.
They are not Visor's source: 16M of someone else's tree does not belong in
this history, and linting it produced 500+ violations that drowned Visor's
own five.

$A"

# ── 2. Shared shell: the extensions every feature below depends on ────────
git add Visor/Window/SkyLightPin.swift
git commit -m "feat(window): pin panels at a chosen SkyLight level

SkyLightPin.pin hardcoded level 100 — above the desktop, below the lock
shield (300), so the island can never paint over a locked screen. The lock
overlay needs the opposite, so the level becomes a parameter with the
existing call keeping its default. Spaces are created once per level and
reused.

Also adds isFullscreenSpaceActive, for the hide-in-fullscreen setting, and
NSScreen helpers (displayUUIDString, isBuiltInDisplay, isDynamicIsland).
Every private symbol stays dlsym-resolved: a macOS that renames one
degrades the feature instead of crashing the app.

$A"

git add Visor/Window/NotchShape.swift VisorTests/CapsuleShapeTests.swift
git commit -m "feat(window): capsule mode for screens with no cutout

On a display without a notch there is no hardware to hide the top edge
behind, so the same shape resolves symmetric corners and reads as a
free-floating capsule.

A branch in NotchShape rather than a second Shape type: one silhouette
morphs between every state, and two shapes could only cross-fade — which
is the rule this codebase is built on. isCapsule is deliberately not
animatable; it follows which screen the island is on, which never changes
mid-animation.

$A"

git add Visor/Window/NotchContentView.swift VisorTests/SwipeAxisTests.swift
git commit -m "feat(gestures): swipe up to dismiss, down to restore

Extends the existing horizontal track-change swipe with a vertical axis
rather than adding a second gesture recogniser beside it.

The direction lock is what makes the two coexist: once one axis leads the
other by 1.25x the gesture commits to it, so a diagonal flick can change
the track or dismiss the island — never both, which is what happened when
each axis was tested independently. resolveAxis is pure and tested.

scrollWheel is split into its three phase handlers; it was one 55-line
function with a complexity of 16.

$A"

# ── 3. Store and layout: the seams the features hang off ──────────────────
git add Visor/Core/Activity.swift Visor/Core/NotchStore.swift Visor/Core/IslandLayout.swift
git commit -m "feat(core): activity kinds, layouts and swipe-dismiss state

Adds the six new ActivityKinds and their place in both priority ladders.
screenRecording sits below nowPlaying in the expanded order for the same
reason timer does: a recording runs for minutes, and hiding the music card
for all of it is worse than showing it only in the wings.

Swipe-dismiss hides an activity without ending it — the feature still owns
it, the user has just asked not to look at it. The dismissal dies with the
thing it dismissed, or a swiped-away track would take every track after it
(caught by a test, not by hand).

Lock state lands here as a *mode*, like onboarding, checked before the
ladder rather than competing inside it.

$A"

git add VisorTests/LockScreenModeTests.swift
git commit -m "test(core): pin the lock-screen and swipe-dismiss seams

LockScreenModeTests guards that nothing about being locked leaks into what
the island resolves. SwipeDismissTests covers the lapse case above.

$A"

# ── 4. Features, each self-contained ──────────────────────────────────────
git add Visor/Features/Download Visor/UI/ExpandedDownloadView.swift VisorTests/DownloadFilterTests.swift
git commit -m "feat(downloads): show files arriving in ~/Downloads

A DispatchSource on the folder, the same mechanism ScreenshotService uses:
the kernel wakes us on a change and nothing runs in between. The reference
implementation also ran a 1s rescan timer to animate progress smoothly —
that is the polling loop the power rules forbid, and it is not needed,
since a download in flight rewrites its own file continuously.

Progress comes from the public com.apple.progress.fractionCompleted
attribute. A file whose app reports nothing gets an indeterminate bar
rather than a guess: the reference's Chromium History SQLite reader was
dropped rather than ported, being an undocumented per-browser schema for
one more progress bar.

Only ~/Downloads is watched. The reference watched five more folders, each
its own TCC prompt on a modern macOS, for files that are rarely downloads.

$A"

git add Visor/Features/AirDrop Visor/UI/ExpandedAirDropView.swift
git commit -m "feat(airdrop): send dropped files with Option held

Outgoing only, via the public NSSharingService. No public API reports an
incoming AirDrop at all, so the reference's 'bidirectional tracking' was
one direction plus a decorative ring.

There is no progress figure here and that is deliberate: macOS reports a
send as started and then finished, with nothing between, so the ring the
reference drew animated a number nobody knew. The glyph carries the state
instead. Files are staged to a temp directory first — the share service
reads them asynchronously and a dropped promise can vanish with the drag.

$A"

git add Visor/Features/ScreenRecording Visor/UI/ExpandedScreenRecordingView.swift VisorTests/ScreenRecordingTests.swift
git commit -m "feat(recording): indicator while the screen is captured

CGSRegisterNotifyProc hands the window server a callback for the two
screen-watcher events; nothing runs until one fires.

Two departures from the reference. The symbols are dlsym-resolved rather
than @_silgen_name'd, so a future macOS dropping one disables the feature
instead of failing to launch. And the elapsed clock is projected from a
stored start date by TimelineView rather than ticked by a 1s Timer — the
same anchor pattern IslandTimer already uses.

$A"

git add Visor/Features/Bluetooth Visor/UI/ExpandedBluetoothView.swift
git commit -m "feat(bluetooth): peek when a device connects or drops

Distributed notifications only. The reference kept a 3s polling timer
behind these as a backstop, which existed to refresh a battery figure
rather than to catch connections — and DeviceBatteryService already reads
that from the IORegistry without a permission.

The device name comes from the notification's own payload. Reading
IOBluetoothDevice.pairedDevices() was tried first and *aborts the
process*: it is privacy-gated, so it demands an
NSBluetoothAlwaysUsageDescription and a permission prompt, for a name
macOS is already handing over. No IOBluetooth import, no prompt.

$A"

git add Visor/Features/Focus
git commit -m "feat(focus): peek when Focus turns on or off

On/off only, via the _NSDoNotDisturb* distributed notifications, which
need no permission.

Naming the active mode is what was dropped: it needs Full Disk Access plus
parsing the undocumented JSON under ~/Library/DoNotDisturb/DB/ — the same
wall that killed notification mirroring, and which the reference's own
code notes became unreliable on macOS 26.

$A"

git add Visor/Features/Network VisorTests/VPNStatusTests.swift
git commit -m "feat(network): VPN indicator gated on the connection, not utun

Extends NetworkService, since this is one more condition of the same
subsystem — the same reason BatteryService owns both the charging peek and
the low/full alerts.

The obvious check is wrong and the reference used it as its primary
signal: macOS creates utun interfaces for Handoff, Continuity and iCloud
Private Relay on a machine with no VPN configured, so an interface-name
check reports a VPN almost permanently. The dynamic store is what is
actually true — a VPN service publishes a State:/Network/Service/<id>/...
key while connected — and matching those IDs names the VPN for free.

Watched with SCDynamicStoreSetNotificationKeys on a .commonModes run-loop
source, so it is event-driven and survives menu tracking.

$A"

# ── 5. Lock screen ────────────────────────────────────────────────────────
git add Visor/UI/Player
git commit -m "feat(player): port the reference's player components verbatim

The equaliser, transport buttons, progress bar, marquee text, liquid-glass
background and artwork backdrop are copied from the GPL-3.0 reference as-is,
so their behaviour matches it exactly rather than approximately. A first pass
rewrote the equaliser from scratch and got it wrong: the real one is
CALayer + CABasicAnimation capped at 24fps, not a per-frame SwiftUI sine.

They are excluded from swiftformat/swiftlint — reformatting them to Visor's
house style would defeat the point of copying them, and would conflict with
any later re-port. Three edits were unavoidable, all forced by Visor's
Swift 6 strict concurrency, which the reference does not build with:
`internal import` -> `import`, `AnimatableModifier` -> `ViewModifier +
Animatable`, and a PreferenceKey's `static var` -> `static let`.

$A"

git add Visor/Features/LockScreen
git commit -m "feat(lockscreen): media panel and padlock, ported from the reference

Three things here are structural and a first pass got all three wrong by
building from a description instead of from the reference's own files:

- The padlock is a *compact activity inside the island*, with its own
  priority and the reference's own width (baseWidth + 55) — not a floating
  panel, which is why it appeared in the wrong place.
- The media panel's window is the *whole screen*; the card positions itself
  with offsets from the centre. A small window under the notch lands wrong
  on every screen size.
- The panel is music-only and music-gated. No calendar, no clock fallback,
  and it appears only when a track is loaded. The last track is cached, so
  locking while paused still shows the player.

Two lock signals, because neither alone suffices: the distributed
notifications are authoritative but arrive once the shield is already up,
while NSWorkspace's session-resign pair fires early enough to be on screen
before it. Combine merges them inside the service; two plain store flags
leave it, so views never see a publisher.

The panel pins above the lock shield. The island's own panel stays pinned
below it, where it has always been — an island that can paint over a locked
screen is a security hole.

Lottie was planned for the latch and dropped: SF Symbols already draws the
lock/lock.open pair with .symbolEffect(.replace). No new SPM package.

$A"

git add Visor/UI/ExpandedMusicView.swift Visor/UI/NotchRootView.swift VisorTests/IslandLayoutTests.swift
git commit -m "feat(music): the island is the player whenever a track is loaded

The music layout carried a date-and-agenda column beside the player. It is
gone: with a track loaded — playing *or paused* — the island is the player
and nothing else, and the agenda is what the idle island shows instead. The
two never share it.

The second column now returns only for the lyrics panel, which
IslandContent.hasLyrics sizes the island for. Music goes 395x197 -> 230x197,
widening back to 395 when lyrics open.

This also fixes the transport row jumping when a track changed: the
reference's fixed MarqueeText frame widths and constant card height are what
stop a longer title reflowing the layout under the controls.

$A"

# ── 6. Now Playing polish ─────────────────────────────────────────────────
git add Visor/Features/NowPlaying/ProgressTintStyle.swift Visor/UI/NowPlayingSeekBar.swift \
        Visor/UI/MusicSeekRow.swift Visor/UI/NowPlayingEqualizer.swift Visor/UI/ExpandedMusicView.swift
git commit -m "feat(music): progress tint styles and an optional equaliser

The scrub bar can take the album's own colour or the system accent,
reusing the existing AlbumColor pipeline rather than the reference's
separate CIAreaAverage one.

The equaliser is honest about being decorative: no public API gives an app
the system's audio levels, so the reference's bars animated random heights
too, and Settings says so. Built on scaleEffect rather than
frame(height:) — animating a layout property in a loop is the exact bug
the power pass measured at 5% CPU. Off by default, and Reduce Motion stops
it outright.

$A"

# ── 7. Customisation ──────────────────────────────────────────────────────
git add Visor/Window/NotchGeometry.swift VisorTests/NotchTrimTests.swift
git commit -m "feat(notch): user width and height trims

Separate from the hardware calibration constants above them, and
deliberately: those are 'what this hardware measures', tuned once against
real machines, while these are 'what this person prefers'. Resetting one
must not lose the other.

Clamped to the Settings range and floored at 8pt, so a stored value from
an older build cannot produce an island too small to right-click — which
is the only way to reach Settings.

$A"

git add Visor/Window/NotchWindowController.swift Visor/UI/NotchRootView.swift \
        Visor/UI/CompactActivityView.swift Visor/Support/Preferences.swift Visor/Support/Log.swift
git commit -m "feat(notch): outline, fullscreen hiding and display selection

Wires the customisation through: the optional outline (skipped entirely
while closed — an outline on the closed island is what 'invisible against
the cutout' forbids), hide-in-fullscreen via the SkyLight space query, and
the display picker.

Also routes the new activities into the compact wings and the expanded
island, and adds the Option-drop AirDrop path to the existing drop target.

$A"

git add Visor/App/SettingsView.swift Visor/App/AppDelegate.swift
git commit -m "feat(settings): Lock Screen and Notch sections, live size feedback

Extends the existing flat-section layout rather than adopting the
reference's sidebar-and-factory settings architecture, which would be pure
overhead at Visor's preference count. The window becomes scrollable, since
it is now taller than a 13-inch screen.

Moving a size trim redraws the island at the new value while the slider
moves, so the numbers can be dialled in by eye rather than guessed and
then checked. Not a new mechanism — it is the ordinary compact peek.

Registers the seven new services.

$A"

# ── 8. Docs and release ───────────────────────────────────────────────────
git add CLAUDE.md
git commit -m "docs: record the port, and condense the progress log

Documents what was ported, what was deliberately not, and the two plan
assumptions that proved wrong on contact (Lottie was unnecessary;
Bluetooth's paired-device list does need a TCC prompt and aborts without
one).

The progress log had grown to ~390 lines against this file's own <200 rule,
so entries before this pass are condensed to one-liners pointing at their
plan files. Back to 201.

$A"

git add README.md
git commit -m "docs: rewrite the README for the new feature set

Covers the lock screen, downloads, AirDrop, recording, Bluetooth, Focus,
VPN and capsule mode, plus tech stack, architecture and a permissions
section — the last of which is the interesting one, since several features
were cut or rebuilt specifically to keep the app at a single prompt.

Fixes the license badge, which still said MIT after the GPL-3.0 relicense.

$A"

git add VisorTests/NotchGeometryTests.swift
git commit -m "test(geometry): stop the user's own notch trim leaking in

closedRect(for:) resolves the width/height trim out of UserDefaults, so the
geometry suite was measuring whatever the sliders were last left on rather
than the geometry. Tests now call the explicit-offset overload.

One canvas assertion also needed a tolerance: the canvas is built by
unioning two rects, which round-trips through the screen maxY, and a
fractional trim makes that lossy by a few ULPs.

$A"

git add Visor/UI/ScreenshotChip.swift VisorTests/ShelfTests.swift
git commit -m "fix(screenshot): make the caught screenshot actually droppable

The chip registered a single file representation for public.fileURL, so the
provider advertised exactly one type. Finder, Slack and Figma all ask for
the image's *content* type instead, found nothing they accepted, and
refused the drop — the catch stored fine and went nowhere.

NSItemProvider(contentsOf:) registers the real type from the file:
public.png alongside the URL types. Measured with a standalone probe before
the change: 1 type before, 3 after.

The dismissal also moves to drag start. The old completion handler only
fired for receivers that asked by URL, so for image apps it was never
reached and the chip stayed in the notch. Removing it from the shelf does
not delete the file, so a receiver can still read it afterwards.

$A"

git add Visor/UI/ExpandedOnboardingView.swift Visor/UI/Player/AnimateImage.swift Visor/Resources
git commit -m "feat(onboarding): animated welcome wordmark, and stop clipping

The secondary \"View GitHub\" link was cut in half. Block.onboardingBody
reserved 92pt for a copy block that draws 119.5, and the step dots were
never reserved at all — measured, the island was 40.5pt short, and the
shortfall came out of the bottom.

The first step now plays the reference's welcome.json: one shape layer with
a gradient fill and a trim path, so the cursive wordmark draws itself on and
loops. Later steps keep their SF Symbol — the animation is the greeting, not
a decoration to repeat three times.

$A"

git add Visor/UI/ExpandedMusicView.swift Visor/Features/NowPlaying/NowPlayingInfo.swift
git commit -m "feat(music): date peek beside the player, cover opens the app

The player keeps a narrow second column: the date block, plus the single
next event when there is one, narrowing to the date alone on a clear day.
Never the full agenda — that stays the idle island's job.

Clicking the album cover activates whichever app is playing, via
NSRunningApplication so the existing instance comes forward rather than a
second one launching. The cover only: a click elsewhere on the island
already means something.

Also closes an 8pt gap along the bottom of the expanded island —
Block.musicColumn reserved 128 for a column that draws 120.

$A"

git add Visor/Features/LockScreen
git commit -m "fix(lockscreen): fade the panel and wing instead of snapping

Both managers animated an isPresented flag the view never saw change: they
mounted at the final value and tore the window down on the same turn, so
neither transition ever ran. Locking and unlocking snapped.

Both now mount hidden and flip on the next turn, and on the way out set the
flag, wait for the animation, then order the window away. The padlock also
grows out of the closed notch and collapses back into it rather than
appearing at full width.

$A"

git add Visor/UI/ExpandedMusicView.swift Visor/Core/IslandLayout.swift VisorTests/IslandLayoutTests.swift
git commit -m "fix(music): the date is a corner box, not a full-height column

As a column it claimed the island's full height for content that only fills
the top of it, so the player was squeezed into the left while a tall strip
of black sat beside it — and the full-height separator drew a line down the
middle of that emptiness.

It is now an overlay in the top-right: it takes only the height it draws,
the player gets the whole width, and only the title row stops short of it.
The box is also fixed — the island used to resize under the player as the
day changed, moving the transport row for a reason nothing on screen
explained. A test pins that 0, 1 and 3 events all give the same size.

$A"

git add Visor/Window/NotchContentView.swift Visor/Core/Motion.swift Visor/UI/NotchRootView.swift
git commit -m "fix(gestures): invert track swipes, and drop the blur

Swiping right now advances, the way flicking a card off a deck does, with
the previous track coming back from the left. Both handlers — the trackpad
swipe and the drag on the card — were following the fingers instead of the
content.

The blur and fade are gone from the swipe entirely. The squeeze alone is
the feedback; blurring the content as well read as the island going out of
focus rather than being pushed, and it smeared the artwork and text for the
whole gesture.

$A"

git add Visor/Features/LockScreen Visor/Window/SkyLightPin.swift
git commit -m "fix(lockscreen): stop SkyLight-pinning the overlay windows

The media panel never appeared. Traced with a probe writing state to a
file, since os.Logger output was not reaching the unified log here: the
panel was created, visible, full-screen and at CGShieldingWindowLevel()
right up until SkyLightPin.pin moved it into a private space whose absolute
level (301) sits *below* the shield. The pin was hiding the very window it
was supposed to lift.

The window level alone already places it above the shield, which is what
the reference relies on too. Verified by counting Visor's on-screen windows
across a lock: 1 before, 3 after — the panel and the padlock, both at
shield level.

$A"

git add Visor/Window/NotchContentView.swift Visor/UI/NotchRootView.swift Visor/Core/NotchStore.swift
git commit -m "fix(gestures): the island no longer shrinks during a swipe

Squeezing the island in proportion to the gesture read as the notch being
dragged about, when all that is happening is the next track starting. The
island now holds still and the swipe simply changes the song.

swipeProgress goes with it: nothing read it any more, and every scroll
event was writing it to the store.

$A"

git add Visor/Core/IslandSpacing.swift Visor/Core/IslandLayout.swift Visor/UI/ExpandedMusicView.swift VisorTests/IslandLayoutTests.swift
git commit -m "style(island): proper insets so the panel stops reading edge-to-edge

The gutter goes 20 -> 26 and the bottom 14 -> 18, the artwork sits 14pt
from the title rather than 10, the rows are 12pt apart rather than 8, and
there is 22pt of clear air before the date box instead of a column gap —
the title and the date are unrelated pieces of information on one line, not
adjacent columns of one thing.

Every layout moves with the gutter, so the pinned sizes move with it:
idle 350x216, music 405x189 (457 with lyrics), timer 360x113.

$A"

git add project.yml new-releases/
git commit -m "release: Visor 1.5 (11)

Adds Lottie (lottie-spm, 4.5.0) for the onboarding wordmark — the one thing
in Visor that uses it.

Build, 164/164 tests, swiftformat and swiftlint (8 warnings, 0 serious) all
pass. The lock overlay is now verified to appear by window count; its
appearance over a real shield still needs your eyes.

$A"

echo
echo "Done. Review with:  git log --oneline -18"
