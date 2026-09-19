# Visor

Native macOS Dynamic Island–style app for the MacBook notch.
Priorities, in order: feels like iOS → near-zero idle power → clean, small codebase.
Full design: docs/RESEARCH.md (source of truth; update it if a decision changes).

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
- Run build, tests, format and lint before saying a task is done.

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
- Do not copy code from GPL projects (boring.notch, Atoll). Reading them for ideas is fine.
- If something is uncertain (private API behavior, macOS version quirks), say so and verify instead of guessing.

## Workflow
- Plan before coding; wait for approval on plans. Don't code until ~98% confident — ask, don't guess.
- Work one phase at a time (see docs/RESEARCH.md §8). Don't start features from later phases.
- Never commit or push — that's the user's call, always.
- Keep MD files lean (this file <200 lines): decisions/architecture/stack/conventions/guidelines/progress only, no verbose prose. Full README treatment only on explicit "update read me".
- Run only necessary shell commands — avoid exploratory bloat.
- When done, report: what changed, how you verified it, what I should test by hand, and any open questions.

## Progress
- **Phase 1 ("The island"):** scaffold implemented (2026-09-15) — project.yml,
  NotchGeometry, NotchShape, NotchPanel/NotchContentView/NotchWindowController,
  NotchStore, Motion tokens, placeholder clock, unit tests. Build, tests,
  swiftformat, swiftlint all pass. Full detail: `~/.claude/plans/tender-waddling-rose.md`.
- **Not yet verified:** the manual checklist in that plan (closed-island
  invisibility, idle CPU, hover feel, interrupt stress test, click-through,
  Reduce Motion, screen reconfig, sleep/wake) — needs the user's eyes on
  real hardware.
- **Phase 2 ("Live activities"):** Tasks 1-9 implemented and reviewed
  (2026-09-16) — Activity model/priority, compact-state geometry,
  activity-driven NotchWindowController, BatteryService + charging peek,
  `mediaremote-adapter` SPM package, NowPlayingService + artwork pipeline,
  compact/expanded Now Playing views, full AppDelegate/NotchRootView
  wiring, plus a post-integration design pass from live hardware feedback
  (charging-detection run-loop-mode fix, expanded layout flanks the camera
  housing, compact view redesigned to battery%+art only). Build, 27/27
  tests, swiftformat, swiftlint all pass. Full detail:
  `.superpowers/sdd/notchy-phase2-live-activities/progress.md`.
- **Phase 3 ("Content layer"):** Tasks 1-10 implemented (2026-09-16) —
  NSVisualEffectView(.hudWindow) material + Reduce Transparency fallback,
  EventKit CalendarService + pure CalendarEventMapper, geometry grown to
  600×220 with chip-bar reservation, ExpandedIdleView/ExpandedMusicView/
  EventRow/MoodChipBar, five new Motion tokens, album-art crossfade+
  scale-pop on track change, threshold swipe gestures, hit-test union for
  the detached chip bar. Build, 34/34 tests, swiftformat, swiftlint (0
  errors) all pass. Spec: `docs/superpowers/specs/2026-09-16-notch-content-layer-design.md`.
  Plan: `docs/superpowers/plans/2026-09-16-notch-content-layer.md`.
- **Dropped:** system-notification mirroring — Notification Center's DB is
  TCC-blocked without Full Disk Access (verified 2026-09-16 on macOS
  26.6.2) and its schema is undocumented. Not worth the permission cost.
- **Layout pass (2026-09-16):** island was rendering 22pt low (NSHostingView
  centred a 176pt root in a 220pt canvas); mood chip bar and "By Apurva"
  signature removed; between-track nil debounced 900ms in NowPlayingService so
  a skip no longer flashes the idle/calendar layout; expanded resized to
  400×186 idle / 400×168 playing (per-layout height, panel frame keeps the
  taller one so it morphs instead of resizing) with a single camera-housing
  clearance; music peek trimmed to one event; transport row given 38×34
  targets under the art + title; `hidesOnDeactivate` disabled so the panel
  survives a Space switch (NSPanel defaults it to true); album-art card flip
  and rising title on track change; trackpad gestures (two-finger swipe =
  track change, two-finger double tap = play/pause) on the panel view;
  `SkyLightPin` moves the panel into a private SkyLight space so desktop
  swipes slide underneath it instead of dragging it along.
- **Phase 3 completion (2026-09-16):** Settings window (version, "by Apurva"
  per §0 attribution, launch-at-login via SMAppService, gesture crib sheet,
  quit) opened by right-clicking the island — an accessory app has no menu
  bar; haptics on both trackpad gestures; `.numericText()` on the battery
  percentage; `PlaybackBars` beat animation. `scripts/make-dmg.sh` builds a
  local ad-hoc `dist/Visor.dmg` (no sharing, no App Store — §0).
- **Cleanup pass (2026-09-16):** −133 lines net. Activity model down to the
  two kinds anything produces (`.timer`/`.hud` return with their features);
  `Activity.expiresAt` dropped — `BatteryService.peekTask` was already the
  only clock that fires; `NotchShape.topRadius` dropped (never drawn);
  calendar colour carried as `Color` instead of a hex round-trip; store
  pass-through setters are plain vars; `AppDelegate` drives `[any
  NotchService]`. Codex findings fixed: `make-dmg.sh` now runs `xcodegen`
  first, and `PlaybackBars` reads Reduce Motion from the environment so it
  stops mid-track.
- **Calendar permission loop:** caused by ad-hoc signing — TCC keys grants to
  the code signature, and every build has a new cdhash. Fix is a stable
  identity: add an Apple ID in Xcode > Settings > Accounts (free tier is
  enough) and set `DEVELOPMENT_TEAM` in project.yml.
- **Power fix (2026-09-16):** ~5% CPU while playing traced by `sample` to
  `PlaybackBars` animating `frame(height:)` — a layout property, so SwiftUI
  re-ran the view graph every frame. Rebuilt on CALayer/CABasicAnimation;
  measured A/B on the same track: **5.2% -> 0.0%**. Also trimmed playback
  position out of `NowPlayingInfo` (adapter re-emits it constantly, nothing
  drew it) and made store activate/deactivate/battery writes compare before
  mutating. Rule added to RESEARCH §5.1b: never animate a layout property in
  a loop.
- **Phase 4 (2026-09-16):** screenshot catcher + album tint, built from
  `docs/superpowers/plans/2026-09-16-screenshot-catcher-ambient-tint.md`.
  `ScreenshotService` watches the screenshot folder with a `DispatchSource`
  (no timer); catches show as a draggable chip with an iOS-style dismiss badge,
  auto-dismiss at 60s, re-armed while hovered. Dragging an image onto the
  island opens it and adopts the file. `AlbumColor` tints the playback bars in OKLab with a chroma
  floor and a lightness lift — the island surface stays pure black. Verified
  live: real screenshot → chip → dismiss, and idle CPU still 0.0%.
- **Phase 5 ("Premium music", 2026-09-16):** album halo behind the artwork
  (pre-blurred once in `ArtworkCache` via CIGaussianBlur, radial-masked,
  `.plusLighter` at 0.55, off under Reduce Transparency/Increase Contrast) —
  started as a panel-wide wash and was cut back after live feedback, so the
  island surface stays pure black in every state; cursor parallax on the album card (±6°,
  `.mouseMoved` on the existing NSTrackingArea, no global monitor); paused art
  desaturates to 0.65 and scales to 0.96; vinyl mode as a **Settings toggle**
  (off by default, not an art-less fallback) on CALayer with the spin removed
  rather than paused. `make-dmg.sh` release names now carry version, build
  number, HH:MM and short commit. Build, 46/46 tests, swiftformat, swiftlint
  (0 serious) all pass. Plan:
  `docs/superpowers/plans/2026-09-16-phase5-premium-music.md`.
- **Cut from Phase 5:** progress-as-bottom-lip (B) — scoped, verified feasible
  (the adapter exposes an elapsed/timestamp/rate anchor plus `setTime`, so it
  needs no timer), dropped by choice before build. Cheap to revive.
- **Audit pass (2026-09-16):** whole-codebase sweep for bugs, waste and hot
  paths. Four fixes, no UI or UX change: (1) `ScreenshotService.scheduleDismiss`
  was a 2s polling loop while the island stayed hovered — replaced with
  `withObservationTracking` on `store.state`, self-terminating on
  `store.screenshot == nil`; (2) `NotchPanel.sendEvent` swallowed every
  double-click inside the silhouette, so double-tapping a transport button or
  the chip's ✕ toggled play/pause instead — the intercept now declines when
  `hostingView.hitTest` finds real content under the point; (3) accessibility
  flags (`reduceMotion`/`reduceTransparency`/`increaseContrast`) were IPC-read
  from view bodies and from `mouseMoved` — now cached in `Motion` and
  refreshed on `accessibilityDisplayOptionsDidChangeNotification`;
  (4) hover-parallax writes gated on the music card being on screen and
  quantised to a 0.02 step, instead of re-rendering at the mouse event rate.
  Also settled the long-standing lint conflict: `--commas inline` in
  `.swiftformat` took swiftlint from 14 warnings to 2. Build, 49/49 tests,
  swiftformat, swiftlint (2 warnings, 0 serious) all pass. Detail:
  RESEARCH.md §5.1c.
- **Known:** two `large_tuple` warnings in `AlbumColorTests` — an RGB triple
  is the honest shape for a colour; left as is.
- **Small-features pass (2026-09-19):** four additions, all built on existing
  mechanisms rather than new ones. Battery compact glyph now tiers symbol +
  colour with charge level (`BatteryGlyph`, matching Control Center) instead
  of always reading `battery.100`/white — visual only, no new peek. New
  `GreetingService` shows a once-a-day "Good morning" compact peek on first
  idle after login or after a `didWake` on a new day, modelled on
  `BatteryService`'s charging peek (`.greeting` activity, lowest priority).
  Idle double-click, previously a silent no-op when nothing was playing
  (`nowPlayingCommands` is set for the app's whole lifetime, so the old code
  called a dead-end adapter toggle), now fires a `.wave` compact peek instead
  — double-click during playback still toggles play/pause unchanged. Settings
  crib sheet restyled from three prose sentences to `ShortcutRow` icon+label
  rows, System Settings–style; no behaviour change. `Haptics` gains two new
  exceptions (`greeting()`, `wave()`) alongside the original `shapeChange()`
  — both one-off, once-a-day-or-rarer, matching the original "chattery"
  finding's bar rather than lowering it. Volume/brightness HUD (also
  proposed) was dropped on the belief it needs a global key monitor —
  **wrong for volume, see the Volume bullet below**; brightness stays
  dropped (private API). Build, 59/59 tests,
  swiftformat, swiftlint (2 warnings, 0 serious — same known large_tuple
  pair) all pass. Plan: `~/.claude-me/plans/wobbly-purring-lollipop.md`.
- **Battery disconnect follow-up (2026-09-19):** the charging peek only ever
  fired on the plug-in edge; unplugging was silent. `BatteryService.refresh`
  now peeks on either edge of the charging transition — the tiered glyph
  itself (bolt vs. `battery.*`) already says which one happened. Latency was
  already effectively zero (IOKit's callback + activity-driven `enterCompact`
  need no hover), so this was a missing case, not a speed problem. Also
  replaced the glyph's onAppear/onChange bounce heuristic — which could
  mis-fire on an unrelated compact peek (screenshot, wave, greeting) — with
  `store.batteryBounceTick`, bumped by the service itself on either edge and
  skipped under Reduce Motion. Build, 59/59 tests, swiftformat, swiftlint (2
  warnings, 0 serious) all pass.
- **Motion pass (2026-09-19):** the "collapses then rounds its corners" bug
  was sequencing, not curves. Measured with an instrumented `Shape`:
  `.logicallyComplete` fires 117ms before the close spring actually lands, so
  `finishShrink`'s `setFrame` clipped the still-protruding bottom corners →
  `.removed` in both `collapseFromExpanded` and `exitCompact` (RESEARCH
  §5.1d). Same harness disproved two plausible-sounding causes: stacked
  `.animation(_:value:)` modifiers do *not* eat the `withAnimation`
  transaction, and per-axis scoped animations cannot desynchronise width from
  height — SwiftUI folds both onto the ambient transaction. `NotchShape`
  rewritten: continuous (squircle) bottom corners via `UnevenRoundedRectangle`
  replacing the hand-rolled arcs, plus the outward-flaring **shoulder**
  RESEARCH §2.5 always wanted, as a concave fillet subpath — `topRadius` 0
  closed (invisibility), 8 compact, 11 expanded. Collapse now carries a
  squash-and-stretch impulse (−20% w / +20% h, held 100ms, radius bulges with
  the stretch), additive on its own spring, with `squashAllowance` headroom in
  the canvas so the overshoot can never be clipped. Content is pinned to its
  resting width and the whole island is `clipShape`d to the silhouette,
  enforcing the "nothing paints outside the shape" rule. Build, 61/61 tests,
  swiftformat, swiftlint (2 known large_tuple) all pass. **Not yet seen on
  hardware.**
- **Reference checkout:** `DynamicNotch/` is a GPL-3.0 clone kept for ideas
  only (CLAUDE.md forbids copying its code). Now gitignored and swiftlint-
  excluded — committing it would vendor GPL source into Visor.
- **Per-feature layout (2026-09-19):** `IslandLayout` replaces the two
  hardcoded expanded sizes and the `hasNowPlaying` branch. Each feature
  declares `expandedExtraWidth/Height`, `compactExtraWidth` and both radii;
  sizes are **deltas from the measured cutout**, not absolutes, so they adapt
  to any notch (on the 15" M4 Air they resolve to the same 400x206/400x168
  the branch produced — guarded by `IslandLayoutTests`). `resolveExpandedKind`
  is the single resolution driving both the size and the view, which fixes a
  latent drift: the compact order puts `.charging` above `.nowPlaying`, so
  sizing the expanded island from it would have blanked the music card
  whenever the charger went in.
- **Motion model ported from DynamicNotch (2026-09-19):** `MotionPreset`
  ladder (snappy/fast/balanced/slow/relaxed, baseResponse 0.41-0.53) with
  every `Motion` token derived from it — expand = base-0.02, close =
  base+0.08, bounce = 1-dampingFraction. Exposed as "Animation speed" in
  Settings. **Note the close is now slower and slightly sprung** (was
  `spring(0.34, bounce: 0)`); NotchKit argues the opposite and the one line
  to flip is documented in `Motion.close`. Swipe-stretch feedback added to
  the *existing* track-change swipe rather than replacing it: the island
  squeezes (clamped 28-44pt) and content blurs/fades while the gesture is
  live, springing back on release.
- **New features (2026-09-19):** `NetworkService` (NWPathMonitor, offline
  alert with OK/Settings, dismissal re-arms on the next path change);
  battery Low/Full alerts on `BatteryService` with pure edge detection in
  `BatteryAlert.crossing` (no Low Power Mode toggle — it needs an admin
  `pmset`, so it points at Settings instead); `TimerService` with preset
  durations from the idle island, deadline-based so nothing ticks behind a
  closed island and `TimelineView` supplies the on-screen clock; the
  screenshot catch became a **4-item shelf** with per-item dismiss, drag-out
  and clear-all, swept by one task rather than one per item. Build, 94/94
  tests, swiftformat, swiftlint (2 known large_tuple) all pass. **None of it
  seen on hardware.**
- **Released:** `new-releases/Visor-1.3(4)-2026-09-19-174655-4945619.dmg`
  (1.3M); the five older DMGs were `git rm`'d at the user's request (still in
  history). Version bumped to 1.3 (build 4).
- **Volume HUD + slider (2026-09-19):** reverses the drop above. The keys
  are never seen; CoreAudio's *result* is. `VolumeService` listens on the
  default output device's `VolumeScalar`/`Mute` via
  `AudioObjectAddPropertyListenerBlock`, plus one on
  `kAudioHardwarePropertyDefaultOutputDevice` so plugging in headphones
  re-targets. Verified with a standalone unsigned CLI probe before any app
  code: F10/F11/F12 all fire, same runloop turn, no Accessibility
  permission, no TCC prompt, no monitor. Two measured quirks the code
  relies on: every change fires the listener **twice** (deduped by
  comparing `VolumeInfo` before writing the store), and at 0 or 100 a
  keypress changes nothing so nothing fires — the island stays shut where
  Control Center's HUD still appears. That gap is the ceiling of the
  no-permission approach and is left open. Expanded layout is a hand-rolled
  draggable bar (`AudioObjectSetPropertyData`, settable confirmed on
  hardware) with optimistic writes so it tracks the pointer; the peek
  refuses to dismiss while the island is expanded, re-arming on collapse
  the way the screenshot shelf does, so it can't vanish mid-drag.
- **Expanded gutter (2026-09-19):** content was laid out at 14pt sides /
  10pt bottom and read edge-to-edge — at the bottom corners the shape
  curves in by its own 28-34pt radius, so content clearing the straight
  edge still ran into the curve. Now 20/14 with the camera clearance at
  +10, applied once in `NotchRootView` rather than per feature, and every
  `expandedExtraHeight` grown 8pt to keep the same content box
  (`IslandLayoutTests` updated: idle 400x214, music 400x176, timer 360x144).
- **Paused music no longer disappears (2026-09-19):** `NowPlayingService`
  called `store.deactivate(.nowPlaying)` whenever `isPlaying` was false, so
  pausing took the whole music layout — transport row included — leaving
  the player's own window as the only way to resume. The activity means "a
  track is loaded", not "audio is coming out"; it now stays active and only
  `scheduleClear`'s 900ms nil grace clears it. Nothing else read it as a
  playback flag (checked every reader). Note: a track paused and abandoned
  now holds the island until its player quits — no idle timeout added.
- **Shoulder seam + motion (2026-09-19):** the pale line separating the top
  curves from the island, and the shoulders reading as a separate piece,
  were one bug. `NotchShape` appended the two shoulder fillets as their own
  closed subpaths, abutting the body along `x = body.minX/maxX`; two
  antialiased edges that merely touch composite to ~75% coverage, not 100%,
  so a hairline ran down each join — worst mid-morph, when the seam sits off
  the pixel grid, which is why it "blended late". Now one region via
  `Path.union` (macOS 14+), skipped entirely when `topRadius == 0` so the
  closed state pays nothing. Second half: the close was
  `baseResponse + 0.08` with `bounce: 0.175`, and the tail of that bounce is
  visible in the shoulders after the body has settled. Flipped to
  `baseResponse - 0.08`, `bounce: 0` — NotchKit's argument, and Visor's
  original number. `unmountDelay` now derives from `closeResponse + 0.06`
  instead of its own ladder, so "content outlives the close" holds
  structurally rather than by two hand-tuned tables agreeing.
- **Content-resolved layouts (2026-09-19):** the "everything is edge to
  edge" complaint had two causes. The gutter (fixed above, 20/14/+10 from
  `IslandSpacing`), and sizing: every layout was a constant tuned for its
  *fullest* state, so a quiet day still got the island a packed one needs.
  `IslandContent` (agenda rows, overflow row, timer presets) now resolves
  size, and totals are added up from named `IslandLayout.Block` heights and
  `IslandLayout.Column` widths instead of typed in — so the numbers to tune
  are the blocks, not the totals, and `IslandLayoutTests` pins what they add
  up to. Reference-hardware results: idle 338x212 with three events,
  **248x143 with none** (was a flat 400x214), music 395x171 with an event
  and 347x171 without, shelf 400x161, battery alert 342x104, timer 360x109,
  volume 360x89. The canvas is unchanged at the max.
- **Agenda rewrite (2026-09-19):** the two-column split balanced at three
  events and fell apart at zero, which is the common case by evening. One
  column beside the date block, an explicit empty state ("Nothing
  scheduled" / "Nothing left today"), and the real bug behind the
  screenshot: `overflow = events.count - shown.count` counted the whole
  day, so two *finished* events printed "2 more events" over an empty
  agenda in a full-height island. `CalendarEventMapper.upcomingCount` is
  now what both the overflow row and the island's height count against.
  Shelf thumbnails centre rather than hugging the left edge (a chip's width
  follows its screenshot's aspect ratio, so the row cannot be sized ahead of
  time); alert detail is `lineLimit(2)`, which is what the height reserves.
- **Device battery (2026-09-19):** Phase C. `DeviceBatteryService` reads
  `AppleDeviceManagementHIDEventService` out of the IORegistry — no
  permission, no Bluetooth framework — and peeks on **connection only**:
  macOS posts nothing when an accessory's charge moves, so a live reading
  would be a poll. `IOServiceAddMatchingNotification` +
  `kIOFirstMatchNotification`, run-loop source in `.commonModes`, initial
  drain suppressed (arming is not a connection event). Lower bud wins; the
  case is ignored; 0 means "not reported", not flat. **Unverified on
  hardware — nothing with a battery was paired when it was written.** To
  confirm: pair AirPods, then
  `ioreg -r -c AppleDeviceManagementHIDEventService -l | grep -i batterypercent`.
  If those keys are named differently the feature stays inert rather than
  misreporting.
- **Not shipped — VPN indicator:** `utun` interfaces exist on macOS without
  any VPN (Handoff and friends use them), so an `NWPath` interface-name
  check false-positives, and the reliable signal (NetworkExtension) needs an
  entitlement Visor will not ask for. Left out rather than shipped as a
  badge that lies.
- **Next:** manual hardware checklists — Phase 2 Task 10 (10 items) and
  Phase 3 Task 11 (16 items, incl. Reduce Transparency/Motion fallbacks,
  chip-bar gating, calendar permission-denied path, closed-state
  invisibility regression guard). Both need the user's eyes on real
  hardware; not automatable.