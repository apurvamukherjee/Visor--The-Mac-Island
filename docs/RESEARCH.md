# Notchy — Research & Technical Design

> A native, Dynamic Island–style notch app for macOS. Goals, in order: **feels like iOS**, **near-zero idle cost**, **clean codebase**.
>
> Research date: 15 Sep 2026. Target dev machine: MacBook Air M4 15" (notched), macOS 26.6.2.

---

## 0. TL;DR decisions

| Decision | Choice | Why |
|---|---|---|
| Language / UI | Swift 6 + SwiftUI, AppKit for the window layer | Only way to get native springs, SF Symbols, system materials, low power |
| Window layer | **Own implementation**, using DynamicNotchKit as a reference | Full control of hit-testing, frame sizing and animation timing, which is where "feel" and power are won or lost |
| Hover detection | **Window frame follows the visible shape** + `NSTrackingArea` | No global mouse monitor → zero CPU while the cursor is elsewhere |
| State | One `@Observable` store + an **activity priority queue** | Mirrors how iOS decides what the island shows |
| Motion | Central `Motion` tokens, springs only, shape leads / content follows | Interruptible, velocity-preserving, consistent |
| Now Playing | `mediaremote-adapter` (BSD-3), long-lived stream process | Only reliable path on macOS 15.4+ |
| Battery | IOKit power-source notifications | Public, event-driven, no polling |
| Project format | **XcodeGen** (`project.yml`) | Agent-friendly; no hand-editing `.pbxproj` |
| Min macOS | 14.0 (Sonoma) | `@Observable`, `withAnimation` completions, `.spring(duration:bounce:)` |
| License | Decide up front (see §1.3) | GPL projects are the best references but can't be copied into an MIT app |
| Distribution | **Offline `.dmg`, ad-hoc/unsigned** — personal use + sharing with friends manually. No App Store, no auto-update server. | No Apple Developer Program yet. Notarized signing stays a Phase 5 item (§8); revisit only if a paid dev account happens. |
| Attribution | **"by Apurva"**, shown once in the app's Settings/About area (Phase 3 settings window) | Keeps the notch UI itself clean, per the "feels like iOS" priority — attribution doesn't belong in the live surface |
| Island material | `NSVisualEffectView(.hudWindow)` under a state-driven black overlay | Closed must stay pure black to masquerade as the hardware notch; the material only reads through once the shape grows past the real cutout. Reduce Transparency falls back to solid fill |
| Expanded size | 600×220 (was 320×120) | The two-column agenda is the point of the idle-expanded state and doesn't fit at 320pt. Accepts more menu-bar overlap while expanded, consistent with the existing overlap decision |
| Expanded-state menu bar overlap | **Accepted** — the hover-expanded island may cover menu bar items, matching Alcove/NotchNook | Closed state must keep everything beside the notch clickable (dead pixels only); expanded is a deliberate, momentary overlay. A menu-bar-clear "shoulder" shape (`topRadius`, currently unused — see §2.5) is a **possible later refinement, not planned** |

---

## 1. Landscape: what already exists on GitHub

### 1.1 Open-source projects worth studying

| Project | License | What to learn from it | Notes |
|---|---|---|---|
| **TheBoredTeam/boring.notch** | GPL-3.0 | Everything: media, visualizer, shelf, calendar, HUD replacement, fullscreen handling | The reference app. ~10.7k stars, actively maintained. Also has **MacroVisionKit** (fullscreen/window-state detection). |
| **Ebullioscopic/Atoll** | GPL-3.0 | Live Activities model (media, focus, screen recording, charging), minimalistic vs standard modes, gesture controls, parallax hover | Forked from boring.notch concepts; explicitly credits Alcove for the minimal-mode design. |
| **monuk7735/mew-notch** (MewNotch) | Check repo | **System HUD replacement + suppression**, brightness/volume, lock-screen notch, per-display selection | Best reference for Phase 5 (HUDs). |
| **Lakr233/NotchDrop** | MIT | File shelf, AirDrop, menu-bar-manager compatibility, minimal architecture | Small, readable, permissive. |
| **MrKai77/DynamicNotchKit** | MIT | Notch window management, **compact state** (iOS-style leading/trailing), continuous-corner shape, stretchy expansion, hover haptics, configurable transitions | Swift 6 concurrency, DocC docs. Best code to read for the window + shape layer. |
| **ungive/mediaremote-adapter** (+ `media-control` CLI) | BSD-3 | Now Playing on macOS 15.4+ | The dependency you actually need. |
| **ejbills/mediaremote-adapter** | MIT | Swift-package wrapper over the same perl-bridge technique, prebuilt binary target | What Notchy actually depends on — see §7.3 |
| **Lakr233/MSDisplayLink** | MIT | Display-link driver for AppKit | Only if you ever need per-frame custom drawing (you probably won't). |
| **GetStream/swiftui-spring-animations** | Check repo | Worked examples of spring parameters | Good for tuning. |

Closed-source inspiration: **Alcove**, **NotchNook**. Study their videos frame-by-frame for timing.

### 1.2 What the good ones have in common

1. The island is **one continuous black shape** that morphs. It never cross-fades between two shapes.
2. A **compact state** exists between closed and expanded: content sits to the left and right of the camera, not under it.
3. **Hover opens, leaving closes**, with a small intent delay. Click-to-open is optional.
4. **Live activities** (music, charging, timers) take over the compact state with a priority order.
5. **Fullscreen awareness**: hide or reduce when a fullscreen app is frontmost.
6. **Per-display behavior** and a sensible fallback for non-notched screens.

### 1.3 Licensing (decide before writing code)

- boring.notch and Atoll are **GPL-3.0**. Copying their code means Notchy must also be GPL-3.0.
- DynamicNotchKit, NotchDrop, MSDisplayLink are **MIT**; mediaremote-adapter is **BSD-3**. Fine for any license, with attribution.
- **Recommendation:** license Notchy **MIT**, write the code yourself, and treat GPL repos as *reading material only*. This also keeps the codebase coherent instead of a patchwork.

---

## 2. What "native iOS feel" actually means

### 2.1 Behavioral rules (from the iPhone Dynamic Island)

| Rule | Implementation |
|---|---|
| The island is a physical object, it stretches, it doesn't teleport | Animate `width`, `height`, and corner radii of **one** `Shape` |
| Shape leads, content follows | Content insertion delayed ~60–100 ms after the shape starts; content removal happens *first* and fast |
| Content materializes, it doesn't just fade | Insert with blur + opacity + slight scale from the top anchor |
| Every animation is interruptible | Springs only. A spring retargeted mid-flight keeps its velocity, so hovering in/out quickly stays smooth |
| Expansion has personality, collapse is calm | Small bounce on open, **zero** bounce on close |
| Idle island is indistinguishable from hardware | Closed shape = exact notch size, pure `#000`, no shadow, no border |
| Depth appears only when open | Shadow fades in with the expanded state only |
| Text changes animate | `.contentTransition(.numericText())` for %, time, counters |
| Icons are alive | SF Symbols `symbolEffect` (`.variableColor`, `.bounce`, `.replace`) |
| Physical feedback | `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, ...)` on open (trackpad) |
| Respect the user | Honor **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`): swap springs for short opacity fades |

### 2.2 Spring guidance (Apple, WWDC23 "Animate with springs")

- Pick the **duration** first for pacing, then add **bounce** for character.
- `bounce: 0` = smooth, critically damped. Around `0.3` is clearly springy; above `0.4` is cartoonish.
- Presets: `.smooth`, `.snappy`, `.bouncy`, and they're tunable: `.snappy(duration: 0.4)`, `.snappy(extraBounce: 0.1)`.
- Use `withAnimation(_:completionCriteria:_:completion:)` for "do X when mostly done" (it uses perceptual duration, not settling time).

### 2.3 Motion tokens (starting values, tune by eye)

```swift
enum Motion {
    /// closed/compact → expanded
    static let open    = Animation.spring(duration: 0.45, bounce: 0.22)
    /// expanded → closed/compact
    static let close   = Animation.spring(duration: 0.34, bounce: 0.0)
    /// closed ↔ compact (live activity appears/disappears)
    static let morph   = Animation.snappy(duration: 0.32)
    /// content insertion
    static let contentIn  = Animation.smooth(duration: 0.28).delay(0.08)
    /// content removal (always faster than the shape)
    static let contentOut = Animation.smooth(duration: 0.14)

    static func resolved(_ a: Animation) -> Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.15) : a
    }
}
```

**Rule:** no raw `.spring(...)`, `.easeInOut`, or magic durations anywhere else in the codebase.

### 2.4 The "materialize" transition

```swift
struct Materialize: ViewModifier {
    let progress: CGFloat          // 1 = hidden, 0 = visible
    func body(content: Content) -> some View {
        content
            .blur(radius: 6 * progress)
            .opacity(1 - progress)
            .scaleEffect(1 - 0.06 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static var island: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: Materialize(progress: 1),
                                 identity: Materialize(progress: 0))
                .animation(Motion.contentIn),
            removal: .modifier(active: Materialize(progress: 1),
                               identity: Materialize(progress: 0))
                .animation(Motion.contentOut)
        )
    }
}
```

Blur is GPU work, but only for ~300 ms during transitions, then it's gone. Never leave a blur on a resting view.

### 2.5 Shape

- Top corners flare **outward** into the menu bar; bottom corners are rounded.
- Use **quad or cubic curves**, and make radii `animatableData` so they morph with size.
- Closed: top ≈ 6, bottom ≈ 10–14. Expanded: top ≈ 14–18, bottom ≈ 24–32.
- Consider continuous-curvature (squircle-like) bottom corners: DynamicNotchKit moved to continuous corners specifically because they read as more polished.
- **Phase 1 status:** the top edge is flush (no flare drawn) — a curve that removes material at the true top corner shows background through a gap right where the shape should meet the bezel. `topRadius` is still tracked/animated for a future outward-flaring shoulder, but since expanded-state menu bar overlap is now accepted (§0), that shoulder is a **possible later refinement, not planned**.

### 2.6 States

```
             hover (intent delay)             leave
closed ───────────────────────────▶ expanded ───────▶ (compact if an activity is live, else closed)
  ▲  │ activity starts                  ▲
  │  ▼                                  │ hover
  compact ──────────────────────────────┘
     │ transient event (charger, HUD)
     ▼
  compact(transient) ──(2–3 s)──▶ previous state
```

---

## 3. Architecture

### 3.1 Module layout

```
Notchy/
├── project.yml                 # XcodeGen spec
├── Notchy/
│   ├── App/                    # @main, AppDelegate, lifecycle
│   ├── Window/                 # NotchPanel, NotchWindowController, geometry
│   ├── Core/
│   │   ├── NotchStore.swift    # @Observable single source of truth
│   │   ├── Activity.swift      # activity model + priority resolution
│   │   └── Motion.swift        # animation tokens
│   ├── Features/
│   │   ├── NowPlaying/         # service + compact view + expanded view
│   │   ├── Battery/
│   │   └── (Timer, Calendar, Shelf, HUD later)
│   ├── UI/                     # NotchShape, NotchRootView, shared components
│   └── Support/                # extensions, logging (os.Logger)
├── NotchyTests/                # geometry, activity priority, parsers
└── Vendor/mediaremote-adapter/ # pinned, with LICENSE
```

Each feature is **self-contained**: a service (data), a compact view, an expanded view, and a registration line. Adding a feature must not touch other features.

### 3.2 Service contract

```swift
@MainActor
protocol NotchService: AnyObject {
    func start()
    func stop()      // must release processes, observers, run-loop sources
}
```

Services push into `NotchStore`; views only read from it.

### 3.3 Activity priority (how the compact state decides what to show)

```swift
enum ActivityKind: Int, Comparable {
    case nowPlaying = 10
    case timer      = 20
    case charging   = 30   // transient
    case hud        = 40   // transient (volume/brightness)
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

struct Activity: Identifiable, Equatable {
    let id: ActivityKind
    var expiresAt: Date?   // nil = persistent
}
```

The store keeps a set of live activities; the highest-priority non-expired one owns the compact state. Transient activities schedule **one** `Task.sleep` for their own expiry (no global ticking timer).

### 3.4 Concurrency

- Swift 6 language mode, strict concurrency **complete**.
- UI + store: `@MainActor`.
- Parsing adapter output and decoding artwork: off the main actor, results hopped back.
- No `DispatchQueue.main.asyncAfter` scattered around; use structured `Task`s owned by the object that cancels them.

---

## 4. The window layer (where power and feel are decided)

### 4.1 Panel configuration

- `NSPanel`, `[.borderless, .nonactivatingPanel]`, clear background, not opaque, no system shadow.
- `level = .mainMenu + 3` (above the menu bar).
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- `LSUIElement = YES` (no Dock icon).
- Position from `NSScreen.safeAreaInsets.top` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.

### 4.2 Hit-testing strategy: "frame follows shape" (recommended)

The common approach (big fixed panel + global mouse monitor + toggling `ignoresMouseEvents`) works, but the global monitor wakes the app on **every mouse move anywhere on screen**. That's the single biggest avoidable idle cost.

Instead:

1. The panel's frame always equals the **bounding box of the currently visible shape** (closed → notch size, compact → compact size, expanded → expanded size), anchored top-center.
2. Inside, a **fixed-size container** (max expanded size) holds the `NSHostingView`, pinned top-center and *not* resized with the window. The window simply crops it.
3. Hover is an `NSTrackingArea` (`.mouseEnteredAndExited, .activeAlways, .inVisibleRect`) on the panel's content view. The OS only calls you when the cursor crosses the island.
4. **Growing:** set the frame to the *target* size first (invisible, since the new area is transparent), then animate the shape.
5. **Shrinking:** animate the shape, then in the `withAnimation` completion set the frame to the new smaller size.
6. The closed-state panel covers only the notch, which is dead pixels anyway, so it blocks nothing.
7. The **expanded**-state panel may cover menu bar items beneath it (§0 — accepted, matching Alcove/NotchNook). Click-through hit-testing on the shape's transparent margins still matters, but not to keep items clickable *under* the solid fill. The hard requirement is the frame shrinking back to the closed rect the instant collapse finishes, so clicks beside the notch pass through immediately again.

Validate in Phase 1 that frame changes cause no flicker or content jump. **Fallback** if they do: fixed max-size panel + global monitor with an early-return rect check.

### 4.3 Fullscreen, spaces, displays

- Observe `NSApplication.didChangeScreenParametersNotification` → recompute geometry.
- Observe `NSWorkspace.activeSpaceDidChangeNotification` + frontmost app changes to detect fullscreen (see TheBoredTeam's MacroVisionKit for approaches) and hide/reduce the island.
- Observe `NSWorkspace.screensDidSleepNotification` / `didWakeNotification` → **stop everything** while asleep.
- Non-notched display: either hide, or render a floating pill (setting).

---

## 5. Performance & power budget

### 5.1 Targets

| State | CPU (Activity Monitor) | Notes |
|---|---|---|
| Idle, nothing playing | **0.0%**, near-zero idle wake-ups | No timers, no monitors firing |
| Compact, music playing | < 0.5% | Only the adapter stream + occasional updates |
| Expanded, animating | Short spikes only | Must settle back to idle within ~0.5 s |
| Memory | < 60 MB | Artwork cache capped |

### 5.2 Rules

1. **Event-driven only.** IOKit notifications, adapter stream, NotificationCenter. No polling loops.
2. **No global mouse monitor** (see §4.2).
3. **Animate views, not windows.** Never call `setFrame` per frame.
4. **Nothing animates when nobody can see it.** Visualizer bars and progress run only while expanded (or compact) *and* playing *and* the screen is awake.
5. **Progress without ticking state.** Store `elapsed` + `timestamp` + `rate`; compute position on render with `TimelineView(.periodic(from: .now, by: 1))`, and only mount that view while expanded.
6. **Fake the visualizer.** A real audio visualizer needs audio capture permission and constant processing. Use a few bars with `phaseAnimator`/`symbolEffect`, paused when not playing.
7. **Artwork:** decode once per track, **downsample** with ImageIO to the display size, cache by track identity (don't re-decode on every diff).
8. **Granular observation.** `@Observable` tracks per property; keep views small so a battery % change doesn't re-evaluate the media view.
9. **Shadows:** only on the expanded state, and prefer a single shadow on the shape over shadows on many subviews.
10. **One long-lived adapter process** for streaming. Commands via short invocations are fine (user-initiated only).
11. **Stop on sleep, resume on wake.** Every service implements `stop()`.
12. **Timers, if unavoidable:** set `tolerance` (≥ 10% of interval) so the OS can coalesce.
13. **Calendar refreshes only on `.EKEventStoreChanged`** (and display wake). No polling, no periodic re-fetch.

```swift
import ImageIO

func downsample(_ data: Data, maxPixels: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}
```

### 5.3 How to measure (do this every phase)

- **Activity Monitor → Energy tab**: Energy Impact, Idle Wake Ups, "Preventing Sleep".
- **Instruments**: Time Profiler, Animation Hitches, SwiftUI (view body updates), Allocations, Energy Log.
- **Xcode debug gauges**: CPU / memory while hovering repeatedly.
- **Stress test**: hover in/out rapidly for 30 s. No stuck states, no dropped frames, CPU returns to 0.

---

## 6. Data sources

### 6.1 Now Playing

- Since **macOS 15.4**, `MediaRemote` only serves Now Playing info to entitled Apple processes; direct private-API use no longer works.
- **mediaremote-adapter** runs a helper through the system's entitled `/usr/bin/perl` and streams JSON to stdout. No SIP changes needed.
- Dev: `brew tap ungive/media-control && brew install media-control`, then `media-control stream` to inspect the real JSON shape.
- Ship: vendor the adapter (script + framework) inside the app bundle, pinned to a version, with its LICENSE.
- Parse defensively: handle `diff` updates by merging; unknown/missing fields → "nothing playing", never crash, never guess.
- Alternative for comparison: JXA/AppleScript approaches exist, but polling-based ones cost more power.
- App Sandbox must be **off** (process spawning).

### 6.2 Battery / power

- `IOPSNotificationCreateRunLoopSource` for change events; read with `IOPSCopyPowerSourcesInfo`.
- Fire a transient `charging` activity on the unplugged → plugged edge only.

### 6.3 Later

| Feature | API | Permission |
|---|---|---|
| Volume changes | CoreAudio property listeners | none |
| Brightness changes | DisplayServices (private) / observed key events | varies |
| Replace system HUD | `CGEventTap` for media keys | Accessibility |
| File shelf | SwiftUI `.onDrop` / `.draggable` | none |
| Timer | pure Swift | none |
| Launch at login | `SMAppService.mainApp` | user toggle |
| Global shortcut | sindresorhus/KeyboardShortcuts (MIT) | none |

---

## 7. Tech stack & what to download

### 7.1 Toolchain status (as of 15 Sep 2026)

- **Xcode 26.6** is the current stable release; **Xcode 27 RC** shipped 9 Sep 2026 and **macOS 27** is about to release.
- **macOS 27 is Apple-silicon-only**, so no Intel concerns for your M4.
- **Liquid Glass** (the design language since the 26 releases) is available on macOS 26+. If you use glass materials in Notchy's settings window or controls, gate with `if #available(macOS 26, *)`. The island itself stays pure black.

### 7.2 Install list

| Tool | Get it from | Purpose |
|---|---|---|
| **Xcode** (26.6 stable, or 27 once final) | Mac App Store | Compiler, SwiftUI previews, Instruments. Check its minimum macOS requirement against your OS version. |
| Xcode Command Line Tools | `xcode-select --install` | CLI builds |
| **Homebrew** | brew.sh | Package manager |
| **media-control** | `brew tap ungive/media-control && brew install media-control` | Now Playing during development |
| **XcodeGen** | `brew install xcodegen` | Generate `.xcodeproj` from `project.yml` |
| **SwiftFormat** | `brew install swiftformat` | Consistent formatting |
| **SwiftLint** | `brew install swiftlint` | Lint rules (no force unwraps, etc.) |
| **xcbeautify** | `brew install xcbeautify` | Readable `xcodebuild` output for Claude Code |
| **gh** | `brew install gh` | GitHub CLI |
| **SF Symbols app** | developer.apple.com/sf-symbols | Browse symbols and their animation support |
| **Claude Code** | Anthropic docs | Agentic development |
| Apple ID | free | Sign & run locally |
| Apple Developer Program | paid, later | Developer ID signing + notarization for distribution |

### 7.3 Swift packages

- **Phase 1–2:** none, except `ejbills/mediaremote-adapter` (MIT-compatible fork of `ungive/mediaremote-adapter`, pinned by commit) for Now Playing — adopted in Phase 2 instead of vendoring the raw adapter, since it ships a prebuilt binary and needs no local cmake/C++ build.
- Later: KeyboardShortcuts (MIT), Sparkle (auto-updates).
- Avoid pulling in DynamicNotchKit as a dependency; read it, don't depend on it (you need control of hit-testing and timing).

---

## 8. Roadmap with acceptance criteria

### Phase 1 — The island (foundation)
- XcodeGen project, Swift 6, SwiftFormat/SwiftLint wired in.
- Geometry from `NSScreen`, `NotchShape` with animatable radii.
- Panel with frame-follows-shape + tracking area; hover intent delay (~120 ms).
- Closed ↔ expanded with `Motion` tokens and the `island` transition (placeholder content).
- **Done when:** idle CPU 0.0%; 30 s of rapid hover shows no glitches; closed island is invisible against the hardware notch; closed-state menu bar items beside the notch are clickable (expanded-state overlap is accepted, §0); collapse releases the expanded area immediately so beside-the-notch clicks pass through again without delay.

### Phase 2 — Live activities
- `NotchStore` + activity priority.
- Battery service → transient charging compact activity.
- Now Playing via adapter → compact (art + bars) and expanded (art, title, artist, controls, progress).
- **Done when:** compact appears/disappears with `Motion.morph`; unplugging/replugging shows the charging peek once; playback controls work; CPU < 0.5% while playing.

### Phase 3 — Polish
- Numeric text transitions, symbol effects, haptics, Reduce Motion.
- Swipe gestures on expanded media (next/previous).
- Content layer: `NSVisualEffectView(.hudWindow)` material behind the shape with a
  state-driven black overlay (closed stays pure black), soft edge bleed, and a
  Reduce Transparency fallback to solid fill.
- Calendar agenda via EventKit (**moved up from Phase 4**): `CalendarService`,
  full-agenda idle-expanded layout, 2-event peek in the music-expanded split.
- Mood/genre chip bar docked under the expanded island while playing (stub actions).
- Expanded size grows to 600×220 to fit the two-column agenda.
- Fullscreen handling, sleep/wake, multi-display, settings window, launch at login.
- Settings/About area shows "by Apurva" once (see §0 Attribution). Power rules
  (§5.2) still apply here: nothing in that window may animate or tick while
  the settings window is closed.

### Phase 4 — Features
- Timer, file shelf. (Calendar moved up to Phase 3.)

### Phase 5 — Advanced
- HUD replacement (Accessibility), vendored adapter, Developer ID signing
  (§0 Distribution — only if a paid dev account happens), notarization,
  Sparkle, Homebrew cask. Until then: offline ad-hoc `.dmg` only.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Apple further restricts MediaRemote | Isolate behind `NowPlayingService`; feature degrades to hidden, app keeps working |
| Frame-follows-shape flickers | Validated in Phase 1; documented fallback |
| macOS 27 changes menu bar / notch behavior | Geometry comes only from `NSScreen` APIs; test on 27 once installed |
| GPL contamination | Read-only use of GPL repos; MIT/BSD deps attributed in `THIRD_PARTY_LICENSES` |
| Scope creep | One phase at a time; each phase has acceptance criteria |

---

## 10. References

- github.com/TheBoredTeam/boring.notch
- github.com/Ebullioscopic/Atoll
- github.com/monuk7735/mew-notch
- github.com/Lakr233/NotchDrop
- github.com/MrKai77/DynamicNotchKit
- github.com/ungive/mediaremote-adapter
- github.com/GetStream/swiftui-spring-animations
- WWDC23 "Animate with springs" (developer.apple.com/videos/play/wwdc2023/10158)
- Apple docs: `NSPanel`, `NSTrackingArea`, `NSScreen.safeAreaInsets`, `IOPSNotificationCreateRunLoopSource`, `SMAppService`, `symbolEffect`, `contentTransition`, ImageIO thumbnails
