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
- **Next:** manual hardware checklists — Phase 2 Task 10 (10 items) and
  Phase 3 Task 11 (16 items, incl. Reduce Transparency/Motion fallbacks,
  chip-bar gating, calendar permission-denied path, closed-state
  invisibility regression guard). Both need the user's eyes on real
  hardware; not automatable.