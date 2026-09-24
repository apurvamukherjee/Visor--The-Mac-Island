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
- **Every `.dmg` ships the styled install window** — background art with the
  drag arrow, both icons placed, no toolbar or status bar. `make-dmg.sh`
  builds read-write, decorates via Finder/AppleScript, then converts to
  compressed read-only; skipping the read-write step silently loses the
  layout. The art is committed at `scripts/dmg/background{,@2x}.png`; a
  release build never regenerates it. Change the art only by editing
  `scripts/dmg/make-background.py` and re-running it (Pillow, dev-only —
  never a build dependency). Icon positions in the AppleScript and the arrow
  endpoints in the script must move together, or the arrow stops pointing at
  anything.
- **The volume ships exactly two visible entries**: `Visor.app` and the
  `Applications` alias (plus `.DS_Store`). The background art lives **inside
  the bundle** at `Visor.app/Contents/Resources/dmg-background.tiff`, so
  nothing extra shows even with `AppleShowAllFiles=1` — `chflags hidden` does
  not hide a root-level dotfile from that setting (verified). Assign it with
  `(POSIX file "…") as alias`; `file "x" of folder "Visor.app" of vol` fails
  -1728 because Finder treats a `.app` as an application, not a folder. The
  art cannot instead be *deleted* before detach: `.DS_Store` stores it as a
  Carbon alias, so the record survives, dangles, and the window paints plain
  grey (measured). `.fseventsd` is deleted **after the rename, immediately
  before detach** — macOS maintains it while the volume is mounted, so an
  earlier delete silently comes back. The art is one multi-resolution `.tiff`
  (`tiffutil -cathidpicheck`), not a `.background/` folder of 1x+2x PNGs.
- **Never let the Finder pass fail silently.** `osascript` must abort the
  build on error, and `.DS_Store` needs a settle before `chflags`/`sync` —
  flagging it while Finder is still writing loses the whole layout, and the
  image still builds, just unstyled.

## Architecture rules
- Single source of truth: `NotchStore` (@Observable, @MainActor). Views read, services write.
- Features live in Features/<Name>/ as service + compact view + expanded view. A feature never imports another feature.
- Every service conforms to `NotchService` with start()/stop(); stop() releases processes, observers, run-loop sources.
- All animations come from `Motion` tokens. No raw .spring/.easeInOut/durations elsewhere.
- One black NotchShape morphs between states. Never cross-fade two shapes.
- **One box for every page, and the same box whatever is playing.** Every
  screen a swipe reaches resolves to one size (`covering`) *and* that size
  always covers `nowPlaying` — the player measures the island. Without the
  second half the box tracked the activity: 421x193 playing, 366x190 not.
- **Chin insets are proportional, never absolute.** A flat inset tuned on the
  idle island measures 2.6% against the player's and stops reading as a card.
- **Chins are short cards.** Draw only the part that shows; a full-height
  chin is 95% hidden and renders the deck as a slab.
- **Depth and the swipe must agree.** The chin you can see is depth +1, so a
  swipe up brings *that* card forward.
- **Anything that lingers gets a page, never the card.** `expandedPriority`
  is ranked by *lifetime*, not importance: a transient alert takes the island
  and leaves, but a screenshot, AirDrop or download sits until dismissed, so
  all three rank below `.nowPlaying` and live on `IslandPage.shelf`. A
  screen that draws nothing is never reachable — `availablePages` gates it.
- **A retraction's wait is derived from its animation, never a constant.**
  `Dwell.stackRetract` is computed from `Motion.retract`; a flat number
  against a preset-scaled spring fires the collapse mid-animation.
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
- Commit after every task, authored as the user (`Apurva Mukherjee
  <apurvan.337@gmail.com>`, GitHub `apurvamukherjee`) from their terminal's
  git config, with a descriptive conventional message and no co-author
  trailer. Never push. (Changed 2026-09-24 at the user's request.)
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
- **DMG background moved into the bundle (2026-09-20):** the volume no longer
  carries a root-level `.background.tiff`, so anyone browsing with
  `AppleShowAllFiles=1` sees two icons rather than three. Two candidate fixes
  were measured on scratch images before the script changed: deleting the art
  before detach **fails** (the `icvp` record holds a Carbon alias, which then
  dangles and paints plain grey), and moving it into
  `Visor.app/Contents/Resources/` **works** — which disproves the earlier note
  that Finder drops a bundle-internal assignment. That note was really an
  AppleScript bug: `folder "Visor.app" of vol` fails -1728 on an application
  bundle, while a POSIX path is accepted. Verified end to end on build16.
- **Volume on external outputs (2026-09-22):** the volume island only ever
  appeared on the built-in speakers. `VolumeService` read
  `kAudioDevicePropertyVolumeScalar` on the **main element**, which exists
  only where the hardware owns a master control — absent on Bluetooth, most
  USB DACs and HDMI, so `read()` returned nil and the feature deactivated
  itself. Now reads/writes/observes
  `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (`'vmvc'`), which
  every measured output has and which returns the identical value on the
  built-in. Four throwaway CoreAudio probes measured it before any app code
  changed (the same probe-first approach the original Volume HUD used):
  per-channel scalar is present but **unbalanced** (0.38/0.37), so averaging
  channels would have drifted. Two corrections fell out: `SystemMute` was
  never broken (mute is main-element everywhere), and "fires twice" is
  device-specific — the soundbar fires 8-16 times, already deduped.
  **Confirmed working on hardware.** No UI change.
- **Phase 6 "the palette and the commands it runs" (2026-09-23):** design in
  `docs/superpowers/specs/2026-09-22-visor-feature-program-design.md`.
  — **Governing rule (§2.1):** nothing changes by default. Every behavioural
  change is a `NewFeature` in a new Settings tab, off until asked for. The
  guarantee is structural, not remembered: `NewFeature` has no `default`
  field and is read with `bool(forKey:)`, so an unwritten key *is* today's
  behaviour, and `resettableKeys` is built from `NewFeatures.all` rather
  than listed by hand. `NewFeaturesTests` pins all of it.
  — **Deletions (~1,100 lines of Swift):** five dead ported views, the
  `notchScale`/`isDynamicIsland` environment nothing ever wrote, dead
  `Motion`/`SkyLightPin` tokens, `LockScreenSettings`' sound keys, and
  **Lottie** — the welcome wordmark is a masked `Text` wipe, so the package
  bought one view. `SystemMute` folded into `VolumeService`,
  `NowPlayingEqualizer` into `PlaybackBars`, three hand-rolled `mm:ss` into
  `Duration.clockText`.
  — **Toggles:** close-intent delay (opening was filtered through 120ms and
  closing through nothing), visible drop zones, swipe-down-opens, hover delay
  as a slider. `Dwell` names all 13 peek durations in one file — **one
  constant per site, not three tiers**: nine services held ten distinct
  values, so tiering them would have moved seven of them, which §2.1 forbids.
  — **Command palette:** ⌃⌥K, a *mode* like onboarding. Typing goes through
  `NotchContentView.keyDown` into the store — no `TextField`, so there is no
  SwiftUI focus to win inside a non-activating panel. 24 commands, each
  gated on a `PaletteContext` so none is offered when it cannot act.
  — **Palette shortcuts:** ⌃⌥K then one key. Rows 1-4 are always numbered;
  letters are bound per command in a Shortcuts settings tab. The rule that
  makes a single key and a search box share one field: **keys fire only
  while the query is empty**. `PaletteShortcutResolutionTests` pins it, and
  the row badges read the same flag so the island cannot advertise a key
  that would not work.
  — **Bugs found by their own compiler warnings:** `VolumeService` retained
  itself (both CoreAudio listener blocks put `[weak self]` on the inner
  `Task`, not on the block CoreAudio holds); its generic read handed a raw
  pointer to an unconstrained `T`; `MarqueeText` polled at 20Hz unbounded
  waiting for a `PreferenceKey`, and scrolled forever ignoring Reduce Motion.
  — **The greeting was half-hidden behind the camera housing.** The compact
  wing was a flat 160pt (64 usable) and "Good afternoon, Apurva" measures
  130. Nothing stopped the row crossing the cutout. Fixed in two places:
  every text label is now clamped to the wing, and the wing is *sized* from
  its label (`Greeting` measures itself once at init — `store.layout` is read
  every animation frame). The greeting name is a Settings field defaulting to
  `NSFullUserName()`'s first word; it was hardcoded to "Apurva".
  — **Probes before code, per §7 of the spec.** All recorded in RESEARCH
  §6.4. The one worth repeating: a probe run from a shell inherits the
  terminal's TCC grant and will tell you `AXIsProcessTrusted == true`.
  Launch it with `open` or the measurement is worthless.
  — Build 0 warnings, 223 tests in 45 suites, swiftformat, swiftlint (6, 0
  serious). ⌃⌥K confirmed firing on hardware; the rest unverified.
- **Launch Groups (2026-09-23):** user-named sets of apps opened together
  (e.g. "Office" -> OpenVPN, a Windows-app client, Chrome) — nothing
  preloaded, entirely user-authored in Settings -> Shortcuts. Ten fixed
  `PaletteCommandID` slots (`.launchGroup1…10`) rather than an open-ended
  list: the codebase already rejected fully dynamic palette rows once (see
  `cycleAudioOutput`'s comment), and a fixed slot stays inside
  `CaseIterable`, the `everyCommandHasAnAction` exhaustiveness test, and —
  the actual win — the existing ⌃⌥K single-key-shortcut mechanism with zero
  new hotkey code. An unconfigured slot never reaches the palette (same rule
  as `switchAudioOutput` with one output), so no new `NewFeature` toggle was
  needed — §2.1 already holds structurally. `LaunchGroup`/`LaunchGroups`
  (`Features/Palette/LaunchGroup.swift`) store bundle identifiers, not
  paths, so a moved app still resolves; `SystemCommands.launch` opens each
  via `NSWorkspace.openApplication` (already used by `openScreenshotTool`,
  no probe needed — it activates rather than relaunches a running app) and
  skips, rather than aborts on, an app that no longer resolves.
  `NotchStore.availablePaletteCommands` is the one place a configured slot's
  placeholder title is swapped for the user's own name and app list.
  `SystemCommands.swift` crossed 400 lines the moment `launch` was added;
  its file-commands extension (already commented "split from the class for
  length") moved to `SystemCommands+Files.swift` rather than let a new
  violation stand. Build 0 warnings, 228 tests in 48 suites, swiftformat,
  swiftlint (6, 0 serious — unchanged). Not yet verified on hardware.
- **AI usage badge (2026-09-23):** today's Claude Code and Codex token use,
  beside the notch. Off by default (`NewFeatures.aiUsageTracker`).
  — **Probed before any code was written**, per §7. Claude Code keeps one
  append-only JSONL per session at `~/.claude/projects/<cwd>/<id>.jsonl`;
  every `assistant` line carries `message.usage`. The CLI and the VS Code
  extension are the same engine writing the same files, so the planned
  "CLI first, else the extension" fallback was **dropped — there is only one
  source**. Codex is different: `codex-cli 0.154.0` keeps SQLite at
  `~/.codex/state_5.sqlite` (WAL) with a `threads.tokens_used` column. Read
  **read-only** through the system SQLite3 C library — no new package. That
  table was empty on this machine, so the Codex path is schema-verified but
  **not verified against real rows**; run a Codex session to close that.
  — **FSEvents, not a `DispatchSource`.** The existing watchers
  (`DownloadService`, `ScreenshotService`) watch one folder's direct
  entries, which would have sat silent here: Claude's transcripts are a
  level deeper, and appending to one does not touch the folder above it. One
  `FSEventStream` covers both roots; its own 0.5s latency does the
  coalescing. `ClaudeUsageReader` keeps a byte offset per file and parses
  only what was appended, so a 2MB transcript is never re-read.
  — **Cache reads are excluded, and that was measured, not assumed.** A real
  day's gross total was 98.6M tokens of which **95.2M (96.5%) were
  `cache_read_input_tokens`** — a function of context length and turn count,
  not of work done. Counting them made the badge read ~99M by mid-afternoon
  whatever the day held. The headline is now input + output + cache
  creation; that day's figure is 3.4M, which moves with the work.
  — **No real plan-limit percentage exists locally.** `policy-limits.json`
  is org compliance settings, not quota; both vendors enforce limits
  server-side and cache nothing. The percentage is therefore progress toward
  a **daily budget the user sets** (Settings → New Features), and no budget
  means no percentage rather than a fabricated denominator.
  — **Its own window, not a slot in the island.** `IslandLayout`'s sizes are
  tight deltas from the measured cutout — the greeting drew half-behind the
  camera housing for exactly that reason — so a permanent element in the
  wings would have moved numbers already tuned. `AIUsageWindowManager` is a
  separate `NSPanel` pinned at the island's own `.aboveDesktop` level (so it
  is *not* on the lock screen), positioned clear of the widest compact wing
  and clamped inside the screen. Nothing in `NotchShape` or `IslandLayout`
  changed. It hides while music owns the island and returns when the island
  is expanded.
  — Marks are the vendors' own, bundled: Claude's 338px app icon and
  OpenAI's SVG, both in `Assets.xcassets`. There is no SF Symbol for either.
  — **Verified on hardware:** the badge renders in the menu bar beside the
  notch showing 3.4M / 68% against a 5M test budget — matching an
  independent count of the same transcripts exactly. Build 0 warnings, 240
  tests in 52 suites, swiftformat, swiftlint (6, 0 serious — unchanged).
  **Not yet seen:** the music hide/return rule, and the Codex figure with
  real data.
- **One box per page + audit (2026-09-23):** paging resized the notch,
  because each of the three screens resolved its own size — so a swipe both
  changed what was showing and moved the shape. Every reachable screen now
  folds into one box (`IslandLayout.covering`), which grows the expanded size
  and keeps the **activity's** own wings and radii. The **player measures the
  box**: 421x193, constant. Measured, not guessed — the agenda at three rows
  plus "+N more" is 178pt against the player's 160, so the agenda *page*
  gives up a row (`maxPagedEventRows` 2, vs `maxEventRows` 3) and the timer
  presets, which stay on the idle home screen. Three rows *without* the
  overflow line would fit (153); the cap is a flat 2 anyway, because a length
  that depends on the calendar is the thing this rule exists to remove.
  Detail: RESEARCH §2.6b. The page swap moved from a bare opacity fade to
  `.transition(.island)` — right while the shape moved under it, wrong once
  it holds still.
  — **Four bugs, all real.** A swipe *up* opened a closed island: paging
  routed both directions through "open it if it isn't up", granting a
  behaviour that belongs to `swipeDownOpens` with that switch off.
  `launchGroupsKey` was declared beside `paletteShortcutsKey` and never added
  to `resettableKeys`, so a restore wiped the shortcut keys and kept the ten
  groups — `PreferencesRestoreTests` iterates that list, so a missing key is
  invisible to it. Two consecutive `Divider()` in `ShortcutsView`. And New
  Features + Shortcuts were hand-rolled `ScrollView`/`VStack` columns while
  the other three panes were grouped `Form`s, so one window held two panes
  that looked like a different app.
  — **Stash:** `adopt` rejected anything not an image and logged it, so a
  dropped video or PDF vanished silently — guard deleted, the thumbnail path
  already falls back to a glyph. New palette command **Stash Clipboard** (37
  commands now): a copied file is held where it lives, copied image data is
  written to a file because the shelf holds URLs and a bare image cannot be
  dropped into Finder; PNG preferred over TIFF (both are on the board after
  ⌃⌘⇧4, the TIFF is the enormous one). `NSPasteboard` injectable, so the
  tests never read the real clipboard. AirDrop never needed a change — it has
  no type filter.
  — `PaletteCommand.Availability` collapsed from nine near-identical cases +
  a nine-arm switch to one `whileTrue(KeyPath<PaletteContext, Bool> &
  Sendable)`; the switch tripped the complexity limit on the tenth gate.
  `& Sendable` is load-bearing under strict concurrency, not decorative.
  — **Audit, listed not applied:** dead `Motion.SwipeFeedback` and
  `Motion`/`MotionPreset.unmountDelay` (both kept alive only by their own
  tests), four byte-identical `Haptics` functions, `PressedButtonStyle`'s
  unused config and dead `#if os(macOS)` branches, `ExpandedUsageView.tools`
  duplicating `NotchStore.usageRows`, and 22 hand-rolled `min(max(…))`
  clamps. ~130 lines, 0 deps.
  Build 0 warnings, 266 tests in 56 suites, swiftformat, swiftlint (3, 0
  serious — **down from 6**). **None of it seen on hardware.**
  **Still open:** dragging an image straight out of a browser is rejected —
  that vends TIFF/PNG *data*, not a file URL, and the drop target is
  `dropDestination(for: URL.self)`.
- **Usage page centering fix (2026-09-23):** reported as the island "hugging
  the top" — really the shared top-alignment every paged screen uses (§2.6b)
  showing through on the one page whose own content is shorter than the box
  driving its height. Only visible with just Claude's usage row present;
  Codex's row closes most of the gap. `.usage` now centers its content
  (`NotchRootView`); the box sizing and other pages' alignment are untouched.
  Build, 266 tests, swiftformat, swiftlint (3, 0 serious — unchanged) all
  pass. Not yet seen on hardware.
- **Card stack paging (2026-09-23):** an optional second way to draw the
  three pages — the front card unchanged, the two adjacent pages peeking
  below it as tinted chins, cycling endlessly both ways. Design in
  `docs/superpowers/specs/2026-09-23-island-card-stack-design.md`; detail in
  RESEARCH §2.6c.
  — **Cross-fade stays the default.** `PagingStyle` is a `Preferences`
  string whose `.crossFade` case is what an unwritten *or unrecognised* key
  resolves to — §2.1's guarantee in a setting that has a value rather than
  an off position. Deliberately *not* in `NewFeatures`: that enum earns its
  guarantee from every member being a bool with no default, and one string
  member would weaken what `NewFeaturesTests` pins. Both new keys went into
  `ownKeys` in the same edit as their declarations — the `launchGroupsKey`
  bug the last audit found — and `PreferencesRestoreTests` names them
  explicitly, since the iteration reads the list and so cannot see a gap.
  — **Depth is the only animated property.** Each card springs to the
  offset/inset/radius its distance from the front implies, inside one
  `withAnimation`; the rise-and-fall falls out rather than being
  choreographed. Three `NotchShape`s translating between depths, never
  cross-fading — growing `NotchShape.path(in:)` into stacked lips was
  rejected because that file is already at swiftlint's limits and one path
  cannot animate its lips independently of its body.
  — **Retract before collapse, and the order is load-bearing.** The
  2026-09-19 motion pass found `setFrame` clipping still-protruding
  geometry; 18pt of chin below the frame is that failure at larger scale.
  `collapseFromExpanded` retracts (`Dwell.stackRetract`, 120ms) and
  re-enters itself, so the frame is never smaller than what is drawn.
  Cancelled on expand, on `stop()`, and on a screen change — a retraction
  surviving any of those would fire a collapse it had already lost.
  — **Front card stays pure black.** Only chins are tinted; full-card tint
  is its own opt-in (`NewFeatures.islandStackTint`, off), because a non-black
  surface already failed twice and a tinted front card is the colour the
  island *closes* in.
  — **Three files split, not three new lint violations.** The work pushed
  `NotchRootView` past the type-body limit and `NotchWindowController` past
  400 lines, so the deck moved to `NotchRootView+Stack.swift` and the
  collapse sequence — already a marked seam — to
  `NotchWindowController+Collapse.swift`, the `SystemCommands+Files.swift`
  precedent. `NotchStore` came back under by tightening this feature's own
  comments rather than moving anyone else's code; its shelf methods were
  tried first and put back, because `shelf` is `private(set)` on purpose and
  an extension in another file cannot write it.
  Build 0 warnings, 287 tests in 59 suites, swiftformat, swiftlint (3, 0
  serious — **back to baseline**). **None of it seen on hardware**; the
  checklist is in the plan's Task 7.
- **Card stack fixed + audit applied (2026-09-23):** the deck shipped in
  2.7.0 did not work on the page it is most often seen on. Measured, not
  guessed: with music playing the shared box is 421x193, and each chin was a
  **full-height card inset a flat 11pt** — 2.6% per side, with 95% of the
  chin hidden behind the front card. The deck rendered as one heavy slab
  with two slivers.
  — **Three fixes, all now rules in RESEARCH §2.6c and above:** insets are a
  fraction of the box (`chinInsetFraction`, floored); chins are short cards
  (`chinBodyHeight`), not full-height ones; one box per page is unchanged and
  now stated as permanent.
  — **Swipe direction was inverted.** Depth counts forward, so the visible
  chin is depth +1, but swipe-up called `cycled(by: -1)` and reached the
  *hidden* depth-2 card. `turned(by:)` now flips the delta for the stacked
  path only; cross-fade is untouched.
  — **Flat tints replaced by `ChinGradient`** — four dark preset families
  (Charcoal/Midnight/Ember/Slate), one Settings picker, each card taking a
  *lighter* stop by depth because darkening runs a chin into the black island
  above it. Unwritten key resolves `.charcoal`, same construction as
  `PagingStyle`. `IslandPage.tint`/`usesMaterialChin` deleted with it.
  — **Audit applied (the /ponytail-audit pass):** deleted `Motion.SwipeFeedback`,
  `Motion`/`MotionPreset.unmountDelay` and their two tests (all alive only via
  their own tests), `NotchStore.focusPeek` (written 3x, read 0x — and an
  `@Observable` write fires a tick), `Dwell.stackReveal` and
  `SystemCommands.isKeepingAwake`. Refactors: `IslandLayout.pill()` factory
  for timer/volume/screenRecording (`NotchRadii(top: 11, bottom: 34)` was
  written out three times), one `Preferences.milliseconds(forKey:…)` behind
  both delay readers, and `Comparable.clamped(to:)` replacing the two private
  clamp helpers two features had each grown.
  — **Cross-fade remains the default throughout**, so an existing install
  sees none of this until the style is selected.
  Build 0 warnings, 288 tests in 59 suites, swiftformat, swiftlint (3, 0
  serious — baseline). **Not yet seen on hardware.**
- **Shelf page + retract timing (2026-09-24):** two reported faults, both
  real, both root-caused rather than patched at the symptom.
  — **Chins faded mid-screen on close.** Three faults on one collapse. The
  wait was a flat 120ms against a retraction riding `Motion.morph`
  (0.41-0.53s by preset), so the collapse started with the chins a quarter
  of the way home; `stackedCard` was gated on `.expanded`, so the deck was
  *removed* from the hierarchy on the state change and took SwiftUI's default
  opacity fade **in place** — the reported symptom exactly; and the
  re-entered `collapseFromExpanded` cleared `isStackRetracting`, sending them
  back out as the squash began. New `Motion.retract` token (bounce 0), a
  computed `Dwell.stackRetract`, the deck surviving to `.closed`, and the
  flag cleared only by `cancelChinRetraction()`. A fourth found on the way:
  the chin's fixed height went negative-offset as the card shrank, poking out
  above it. The 2.8.0 entry fixed *when* the chins tuck, not whether anything
  remained to tuck — this supersedes it.
  — **A screenshot killed the music card.** `.screenshot`/`.airDrop`/
  `.download` outranked `.nowPlaying` in `expandedPriority`, and the shelf
  was the home page's *content*, so no swipe recovered the player. All three
  moved below music — the same lifetime test already applied to `.timer` —
  and the shelf became `IslandPage.shelf` (raw `-2`), present only while
  `hasShelfContent`, which reads `activities` so availability and the ladder
  cannot drift. `compactPriority` untouched: a catch still peeks in the
  wings. Three existing tests encoded the old rules and were updated, not
  deleted; one (`pagingDoesNotResize`) was iterating `allCases` rather than
  `availablePages` and is now joined by the case that matters — a catch and
  a track at once, the first time the shelf's layout is in the shared box.
  Build 0 warnings, 299 tests in 61 suites, swiftformat, swiftlint (3, 0
  serious — baseline). Detail: RESEARCH §2.6c, §2.6d. **Not seen on
  hardware.**
- **Next:** `docs/HARDWARE-CHECKLIST.md` — the one manual list, ordered by
  machine state rather than by phase, superseding Phase 2 Task 10, Phase 3
  Task 11 and the card stack's Task 7 (all three kept as history, none
  maintained). Written 2026-09-24 after an audit found five of their items
  testing UI that no longer exists: the expanded island's clock/battery row,
  the music card's calendar column and the mood chip bar were all cut, and
  "Phase 3 Task 11, 16 items" named a list that exists nowhere — the spec has
  10. Needs the user's eyes on real hardware; not automatable.
  Audit and the plan behind it:
  `docs/superpowers/plans/2026-09-24-pending-and-replan.md`.