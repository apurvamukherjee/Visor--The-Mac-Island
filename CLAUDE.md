# Visor

Native macOS Dynamic Island–style app for the MacBook notch.
Priorities, in order: feels like iOS → near-zero idle power → clean, small codebase.
Full design: docs/RESEARCH.md (source of truth; update it if a decision changes).
License: GPL-3.0 (see `LICENSE`, added 2026-09-19 so GPL-licensed reference code can be ported in — see Progress).

## Stack
- Swift 6 language mode, strict concurrency: complete
- SwiftUI for all views; AppKit only in Window/ and App/
- macOS 14.0 minimum, Apple silicon
- XcodeGen: edit project.yml, never edit .pbxproj; run `xcodegen generate` after changes
- No third-party Swift packages unless I approve them
- App Sandbox off (spawns the media adapter); LSUIElement = YES

## Commands
- Generate: `xcodegen generate`
- Build: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
- Test: `xcodebuild -scheme Visor test | xcbeautify`
- Format: `swiftformat .`   Lint: `swiftlint`
- Release: `bash scripts/make-dmg.sh`
- Run build, tests, format and lint before saying a task is done.

## Releases
- **Semantic versioning, always.** `MARKETING_VERSION` is `MAJOR.MINOR.PATCH`:
  MAJOR changes how the island behaves for someone already using it, MINOR
  adds a feature, PATCH fixes without adding one. `make-dmg.sh` *rejects* a
  version that is not three numbers, so the convention cannot lapse quietly.
- Every release build goes in `new-releases/` as a new `.dmg`, committed,
  named `Visor-<version>-build<n>-<date>-<time>-<commit>.dmg`.
- **Never delete or overwrite an old build.** They are permanent history:
  `make-dmg.sh` refuses to overwrite a release already on disk, and the
  folder is meant to accumulate. Removing one is a regression, not tidying.
  (Builds up to 1.6.0 used an older `Visor-1.6(12)-…` name and were renamed
  in place with `git mv` when this convention was adopted — bytes and history
  unchanged. That was a rename, not a deletion.)
- Bump `MARKETING_VERSION` *and* `CURRENT_PROJECT_VERSION` in project.yml
  before building, so each DMG gets its own name — the hash in the filename
  is `HEAD` *at build time*, so commit first.
- Record every release in `CHANGELOG.md`: Added / Changed / Fixed, plus
  anything deliberately left out and why.

## Architecture rules
- Single source of truth: `NotchStore` (@Observable, @MainActor). Views read, services write.
- Features live in Features/<Name>/ as service + compact view + expanded view. A feature never imports another feature.
- Every service conforms to `NotchService` with start()/stop(); stop() releases processes, observers, run-loop sources.
- All animations come from `Motion` tokens. No raw .spring/.easeInOut/durations elsewhere.
- One black NotchShape morphs between states. Never cross-fade two shapes.
- Shape leads, content follows (content in delayed, content out fast).
- Respect Reduce Motion.

## Power rules (non-negotiable)
- Event-driven only. No polling loops. No global mouse monitors.
- Panel frame follows the visible shape; hover via NSTrackingArea.
- Never animate window frames per frame; animate SwiftUI views.
- Nothing animates or ticks when not visible, not playing, or display asleep.
- Artwork decoded once per track and downsampled with ImageIO.
- Timers only if unavoidable, always with tolerance.

## Code quality
- Small files, small views, clear names. No god objects.
- No force unwraps, no `try!`, no print(); use os.Logger with a subsystem.
- No commented-out code, no TODOs without an issue reference, no placeholder "example" code left behind.
- Comments explain *why*, not *what*.
- Unit-test pure logic: geometry, activity priority, adapter JSON parsing.
- Visor is GPL-3.0 (see `LICENSE`), so porting code from other GPL-3.0 projects (boring.notch, Atoll, DynamicNotch) is allowed — still reimplement rather than blind-paste where Visor's own architecture (NotchService, Motion tokens, @Observable store) differs, and still no third-party packages without approval (line above) even if the reference project uses one.
- If something is uncertain (private API behavior, macOS version quirks), say so and verify instead of guessing.

## Workflow
- Plan before coding; wait for approval on plans. Don't code until ~98% confident — ask, don't guess.
- Work one phase at a time (see docs/RESEARCH.md §8). Don't start features from later phases.
- Never commit or push — that's the user's call, always.
- Keep MD files lean (this file <200 lines): decisions/architecture/stack/conventions/guidelines/progress only, no verbose prose. Full README treatment only on explicit "update read me".
- Run only necessary shell commands — avoid exploratory bloat.
- When done, report: what changed, how you verified it, what I should test by hand, and any open questions.

## Progress
Phases 1-5 and the passes after them are summarised below; each named plan
file holds the full detail. Anything still unverified on hardware is flagged.

- **Phase 1 "The island" (2026-09-15):** shell scaffold — project.yml,
  NotchGeometry/NotchShape/NotchPanel/NotchWindowController, NotchStore,
  Motion tokens. Plan: `~/.claude/plans/tender-waddling-rose.md`.
- **Phase 2 "Live activities" (2026-09-16):** Activity model + priority,
  BatteryService, `mediaremote-adapter` (the one approved SPM package),
  NowPlayingService + artwork pipeline. Detail:
  `.superpowers/sdd/notchy-phase2-live-activities/progress.md`.
- **Phase 3 "Content layer" (2026-09-16):** EventKit CalendarService +
  pure CalendarEventMapper, expanded idle/music views, swipe gestures,
  Settings window (right-click the island — an accessory app has no menu
  bar), `scripts/make-dmg.sh`. Plan:
  `docs/superpowers/plans/2026-09-16-notch-content-layer.md`.
- **Phase 4 (2026-09-16):** screenshot catcher (DispatchSource, no timer)
  + `AlbumColor` OKLab tinting.
- **Phase 5 "Premium music" (2026-09-16):** album halo, cursor parallax,
  vinyl mode (a Settings toggle, not an art-less fallback). Plan:
  `docs/superpowers/plans/2026-09-16-phase5-premium-music.md`.
  **Cut by choice:** progress-as-bottom-lip — scoped, feasible, cheap to
  revive.
- **Power fix (2026-09-16):** ~5% CPU while playing traced to
  `PlaybackBars` animating `frame(height:)` — a *layout* property, so
  SwiftUI re-ran the view graph every frame. Rebuilt on CALayer:
  **5.2% -> 0.0%** measured A/B. Rule in RESEARCH §5.1b: never animate a
  layout property in a loop.
- **Audit pass (2026-09-16):** four fixes, no UX change — a 2s polling
  loop in `ScreenshotService` replaced with `withObservationTracking`;
  `NotchPanel.sendEvent` no longer swallows double-clicks landing on real
  controls; accessibility flags cached in `Motion` (each raw read is an IPC
  round-trip); hover-parallax writes gated and quantised. Detail:
  RESEARCH §5.1c.
- **Motion pass (2026-09-19):** the "collapses then rounds its corners" bug
  was *sequencing*, not curves — `.logicallyComplete` fires 117ms before the
  close spring lands, so `setFrame` clipped the still-protruding corners.
  Fixed with `.removed` (RESEARCH §5.1d). Same harness disproved two
  plausible causes: stacked `.animation(_:value:)` do *not* eat the
  `withAnimation` transaction, and per-axis scoped animations cannot
  desynchronise width from height. `NotchShape` rewritten with continuous
  bottom corners and the outward-flaring shoulder as a unioned fillet —
  appended subpaths left a pale seam, because two antialiased edges that
  merely abut composite to ~75% coverage, not 100%.
- **Per-feature layout (2026-09-19):** `IslandLayout` replaced two hardcoded
  sizes; every size is a **delta from the measured cutout**, so layouts land
  on any notch. `resolveExpandedKind` is the single resolution driving both
  size and view, fixing a latent drift (the compact order puts `.charging`
  above `.nowPlaying`, so sizing from it would blank the music card whenever
  the charger went in).
- **Content-resolved layouts + agenda rewrite (2026-09-19):** sizes resolve
  from `IslandContent`, so a quiet day gets a smaller island rather than the
  same island with black in it. Real bug found: overflow counted the *whole*
  day, printing "2 more events" over an empty agenda.
- **Motion model + new features (2026-09-19):** `MotionPreset` ladder
  exposed as "Animation speed"; `NetworkService`, battery Low/Full alerts,
  `TimerService`, the 4-item screenshot shelf.
- **Volume HUD (2026-09-19):** reverses an earlier drop. The keys are never
  seen; CoreAudio's *result* is. Verified with a standalone CLI probe before
  any app code. Two measured quirks the code relies on: every change fires
  the listener **twice** (deduped), and at 0 or 100 a keypress changes
  nothing so nothing fires — that gap is the ceiling of the no-permission
  approach and is left open.
- **Device battery (2026-09-19):** `DeviceBatteryService` reads the
  IORegistry — no permission, no Bluetooth framework — and peeks on
  **connection only**: macOS posts nothing when an accessory's charge moves,
  so a live reading would be a poll. **Unverified on hardware.** To confirm:
  `ioreg -r -c AppleDeviceManagementHIDEventService -l | grep -i batterypercent`.
- **Welcome/Player/Settings (2026-09-19):** three-step onboarding that lives
  *inside* the panel as a mode orthogonal to the activity ladder (the
  precedent the lock screen later followed); seek bar, shuffle/repeat, and a
  lyrics panel that fetches only while open. Position is a
  `NowPlayingProgress` **anchor**, written only on a real event — everything
  else reads it live through `TimelineView`, so the per-tick store rewrite
  the power pass removed did not come back.
- **Dropped, each for a stated reason:** system-notification mirroring
  (Notification Center's DB is TCC-blocked without Full Disk Access,
  verified 2026-09-16, schema undocumented); VPN-by-interface-name (`utun`
  exists without any VPN, so it false-positives — later shipped properly via
  SCDynamicStore); AirPlay route button (`AVRoutePickerView` routes the
  *calling app's* audio, and Visor produces none); favourite-track button
  (AppleScript automation = a new per-app TCC prompt for one star icon).
- **Known:** two `large_tuple` warnings in `AlbumColorTests` — an RGB triple
  is the honest shape for a colour; left as is.
- **Calendar permission loop:** caused by ad-hoc signing — TCC keys grants to
  the code signature, and every build has a new cdhash. Fix is a stable
  identity: add an Apple ID in Xcode > Settings > Accounts (free tier is
  enough) and set `DEVELOPMENT_TEAM` in project.yml.
- **Reference checkouts:** `DynamicNotch/` and `old-code/` are GPL-3.0
  clones kept for porting from, excluded from swiftformat/swiftlint.
- **old-code port (2026-09-19):** ported the feature set of a ~350-file
  alternate Dynamic Island app into Visor's own architecture. Its competing
  shell (NotchEngine/NotchModel/NotchViewModel/DynamicIslandShape) was *not*
  ported — every feature's logic and views were rehomed onto Visor's single
  `NotchStore` + `Activity` ladder + `IslandLayout` + `NotchShape` + `Motion`
  shell, which was extended rather than duplicated.
  — **Shell:** `SkyLightPin.pin` takes a `Level` (the island keeps 100, below
  the lock shield; the lock overlay pins 301/302 above it) and gained
  `isFullscreenSpaceActive`; `NotchShape` grew an `isCapsule` branch for
  screens with no cutout (one shape, per the never-cross-fade rule, not
  old-code's separate `DynamicIslandShape`); `scrollWheel` gained a vertical
  axis with a 1.25x direction lock so swipe-to-dismiss cannot collide with
  the existing track-change swipe.
  — **Lock screen:** `LockScreenService` (distributed lock/unlock plus the
  `sessionDidResignActive` pre-lock edge, merged through Combine internally,
  out as two plain store flags) and `LockScreenWindowController`, two panels
  above `CGShieldingWindowLevel()`. Lock is a *mode* like onboarding, checked
  before the activity ladder — `LockScreenModeTests` pins that seam. Widget
  shows the player when something is playing and clock+agenda when not; they
  never share the card.
  — **New activities:** Downloads (FSEvents on ~/Downloads + the public
  `com.apple.progress.fractionCompleted` xattr — *not* old-code's 1s rescan
  timer), AirDrop (outgoing only via `NSSharingService`; Option-drop on the
  island), Screen Recording (`CGSRegisterNotifyProc`, `dlsym`-resolved so a
  missing symbol degrades instead of crashing like old-code's
  `@_silgen_name`), Bluetooth connect/disconnect, Focus on/off, VPN.
  — **Now Playing:** progress tint style (standard/album/accent), optional
  decorative equaliser (scale, never `frame(height:)` — RESEARCH §5.1b).
  — **Customization:** stroke, ±16pt/±4pt notch trims with live feedback,
  fullscreen hide, display selection.
  — **Deliberately not ported, each for a stated reason:** Focus mode
  *names* (needs FDA + undocumented JSON — the notification-mirroring wall);
  Apple Clock timer mirroring (private prefs + log scraping + AX automation +
  1s poll); media-key HUD (global CGEventTap + Accessibility); Hotspot
  (private `Sharing.framework`); Bluetooth battery fusion (5 scraped sources
  + 3s poll — `DeviceBatteryService` already covers it); Chromium History
  scraping; FileConverter/HomePage/SystemStats (never requested).
  — **Two plan assumptions proved wrong on contact:** (1) Lottie was dropped
  — SF Symbols' `lock`/`lock.open` pair with `.symbolEffect(.replace)` draws
  the latch natively, so the dependency bought nothing; **no new SPM package
  was added**. (2) "Bluetooth alerts need no new TCC prompt" was right only
  for the notification — `IOBluetoothDevice.pairedDevices()` is privacy-gated
  and *aborted the process* at launch under the test host with no
  `NSBluetoothAlwaysUsageDescription`. Rewritten to read the notification's
  own payload; no IOBluetooth import, no prompt.
  Build, 158/158 tests, swiftformat, swiftlint (5 warnings, 0 serious — the 2
  known `large_tuple` plus 3 size/complexity on shapes CLAUDE.md prescribes)
  all pass. `old-code/` and `DynamicNotch/` added to the swiftformat/swiftlint
  exclusions — reference checkouts, not Visor's source.
  **None of it seen on hardware.** Highest-uncertainty item by far: whether
  the lock overlay actually paints above the real lock shield.
- **Lock-screen correction (2026-09-19):** the first pass built the lock
  screen from the plan's description rather than from old-code, and got three
  structural things wrong. Rewritten by copying the reference's files.
  — The padlock is a **compact activity inside the island**
  (`LockScreenNotchContent`, its own priority, `baseWidth + 55`), not a
  floating panel. That is why it was misplaced.
  — The media panel's window is the **whole screen** (`screen.frame`); the
  card positions itself with offsets from the centre
  (`panelCenterYOffset = panelSize.height / 2 + 80`). A small window under
  the notch puts it in the wrong place on every screen size.
  — The panel is **music-only and music-gated**: no calendar, no clock
  fallback, and it appears only when a track is loaded. The last track is
  cached so locking while paused still shows the player.
  Copied verbatim from old-code: `LightweightNowPlayingEqualizerView`
  (CALayer + CABasicAnimation at a capped 24fps, not the sine version the
  first pass invented), `PlayerControlButton`, `PlayerProgressBar`,
  `MarqueeText`, `LiquidGlassBackground`, `NowPlayingArtworkBackground`,
  `LockScreenClockView`, `LockScreenWidgetSurface`, `LockScreenSettings` and
  its style enums. They live in `Visor/UI/Player/` and are **excluded from
  swiftformat/swiftlint** — reformatting them would defeat the point of
  copying them. Three edits were unavoidable: `internal import` -> `import`,
  `AnimatableModifier` -> `ViewModifier + Animatable`, and a
  `PreferenceKey`'s `static var` -> `static let`, all forced by Visor's
  Swift 6 strict concurrency, which old-code does not build with.
- **Lock-screen bugs + player pass (2026-09-19):** three reported faults,
  all real.
  — **The notch did not appear while locked.** The island's own panel is
  pinned *below* the lock shield by design, so it is invisible there. The
  padlock therefore needs a window of its own above the shield, which is
  what the reference's `LockScreenLiveActivityWindowManager` is for — a file
  the first pass missed entirely. Added as
  `LockScreenNotchWindowManager` at `CGShieldingWindowLevel() + 1`, pinned
  `.aboveLockShieldNotch`, `ignoresMouseEvents`.
  — **The widget lingered ~1s after unlock.** `isLockPresenting` was
  `isLocked || isLockTransitioning`, and the transition flag carries the
  820ms unlock settle. The reference gates its panel on
  `isLocked || isPreparingLock` and lets the settle drive only
  `isLockIdle`, which nothing drawn on the lock screen reads. Split into
  `isPreparingLock` (pre-lock edge) and `isLockTransitioning` (unlock
  animation, over the desktop); `isLockPresenting` no longer reads the
  latter.
  — **The expanded player was too thin.** Dropping the calendar column left
  it at 230pt — *narrower than the 345pt compact wing it opens from*, so
  expanding shrank the island sideways. `nowPlaying` now floors
  `expandedExtraWidth` at `compactExtraWidth + 60`; music resolves to
  405x185 (445 with lyrics), and `IslandLayoutTests` pins that the expanded
  player is never narrower than its own wing.
  Player rebuilt on old-code's components throughout: `PlayerControlButton`
  (press pulse, scale, directional nudge), `PlayerProgressBar` (inline
  times, thickens under a drag) and `MarqueeText` at a **fixed** width —
  that last one is what stops the transport row jumping on track change,
  since a self-sizing `Text` reflows the column under it. `Block.musicColumn`
  140 -> 128, `Column.music` 190 -> 240.
  — Also found by the tests, not by hand: `NotchGeometry.closedRect(for:)`
  reads the user's trim from `UserDefaults`, so the developer's own slider
  values leaked into the geometry suite. Tests now call the explicit-offset
  overload. One canvas assertion needed a tolerance: unioning two rects
  round-trips through the screen's maxY, which a fractional trim makes lossy
  by a few ULPs.
- **Calendar/music exclusivity (2026-09-19):** `ExpandedMusicView` carried a
  date-and-agenda column beside the player. Removed: with a track loaded —
  **playing or paused** — the island is the player and nothing else, and the
  agenda is what the *idle* island shows. The second column now returns only
  for the lyrics panel, which `IslandContent.hasLyrics` sizes the island for.
  Music went 395x197 -> 230x197, widening back to 395 with lyrics open.
  Fixes the transport row jumping on track change: the reference's fixed
  `MarqueeText` frame widths and constant card height are what stop a longer
  title reflowing the layout under the controls.
- **Lock-screen pin + insets + pause collapse (2026-09-20):** three fixes.
  — **Neither lock window appeared.** A prior pass removed `SkyLightPin.pin`
  from both lock managers, reasoning that `CGShieldingWindowLevel()` is
  already above the shield. It is not: the real shield sits at that same
  level and is ordered above, so only a SkyLight space past absolute level
  300 paints over it. Restored in both, with the `hasPinned` bookkeeping —
  the pin must follow `orderFrontRegardless`, since `windowNumber` is only
  valid once a window is on screen.
  — **Expanded content read edge-to-edge** at a 26pt gutter: the artwork's
  halo and the date's digits sit at the extremes, so the eye measures from
  the glow, not the frame. Gutter 26 -> 34, bottom 18 -> 22. Raising the
  gutter alone would have squeezed the player instead of insetting it —
  `nowPlaying` resolves `max(content, floor)` and the floor was binding, so
  `musicExpandMargin` went 60 -> 76. Music 421x193 (473 with lyrics).
  — **Pause now collapses the island** to the bare notch after 5s, which
  *reverses* the "playing or paused, the island is the player" rule above.
  Ported from old-code's pause-hide timer (same 5s), minus its setting and
  its defer-while-expanded: collapse is unconditional here. The delay is the
  point — a pause is usually a step on the way to a skip or a seek, and an
  island that shuts instantly flaps around every one of them. The track is
  **not** cleared, only `.nowPlaying` deactivated, so opening the island by
  hand still finds a transport row to press play on; `PauseCollapseTests`
  pins that seam. Re-arming is gated on `store.isActive` — the adapter
  re-emits on every position tick, and re-arming per tick would push the
  deadline out forever. The lock-screen media panel gates on `isPlaying`
  too, so a paused track shows no panel there either.
- **Next:** manual hardware checklists — Phase 2 Task 10 (10 items) and
  Phase 3 Task 11 (16 items, incl. Reduce Transparency/Motion fallbacks,
  chip-bar gating, calendar permission-denied path, closed-state
  invisibility regression guard). Both need the user's eyes on real
  hardware; not automatable.