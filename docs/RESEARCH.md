# Visor — Research & Technical Design

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
| Release history | Semver'd, dated `.dmg` committed to `new-releases/` by `scripts/make-dmg.sh`; changes recorded in `CHANGELOG.md` | Downloadable straight from the GitHub file listing without needing the Releases UI or a tag. ~1MB per build; if the repo ever feels heavy, move the history to GitHub Releases and keep only the newest here |
| `.dmg` window | **Styled install window**: committed background art (notch mark, wordmark, arrow) at `scripts/dmg/background{,@2x}.png`, `Visor.app` at {145,170} and the `/Applications` alias at {395,170} in a 540x400 window, no toolbar, no status bar | A bare `.dmg` shows two unexplained icons in a list; the arrow is what every Mac user already reads as "drag left onto right". The layout lives in the volume's `.DS_Store`, which Finder only writes to a **mounted read-write** disk — so `make-dmg.sh` creates UDRW, runs the Finder AppleScript, `sync`s, detaches, then `hdiutil convert`s to UDZO. Creating UDZO directly, or skipping the sync, drops the layout with no error. Art is generated once by `scripts/dmg/make-background.py` (Pillow) and committed, so a release build needs no Python. The art is staged into `Visor.app/Contents/Resources/dmg-background.tiff` and assigned by POSIX path, so the volume shows no background file of its own |
| `.dmg` hygiene | Volume ships **two visible entries only**: `Visor.app` and the `Applications` alias, plus `.DS_Store`. The background art lives **inside the bundle** at `Visor.app/Contents/Resources/dmg-background.tiff`; `.fseventsd` deleted after the rename, just before detach | A root-level `.background.tiff` is a real window entry for anyone with `AppleShowAllFiles=1`, and `chflags hidden` does **not** hide it from them (verified — Finder lists flagged items anyway); the leading dot only hides it at the default setting. Putting the art in the bundle removes the entry for everyone. **Corrects an earlier note** that claimed art cannot live inside `Visor.app`: that failure was the AppleScript, not Finder — `file "x" of folder "Visor.app" of vol` fails -1728 because Finder treats a `.app` as an application, not a folder, while `(POSIX file "…") as alias` is accepted and writes a correct `icvp` record (measured 2026-09-20, build16). The art also cannot simply be deleted before detach: `.DS_Store` stores the background as a Carbon **alias** to a real file, so the record survives but dangles and the window paints plain grey (measured). `tiffutil -cathidpicheck` still packs 1x+2x into one file. Ordering stays load-bearing: macOS recreates `.fseventsd` while the volume is mounted writable, and the rename invalidates the old mount path. `SetFile -a V` is the deprecated spelling and silently fails |
| Code signing | **Free Apple Development identity** (Xcode > Settings > Accounts, no paid program) | Not for distribution — for TCC. Permissions are bound to the code signature; ad-hoc signing changes the cdhash every build, so macOS re-asked for calendar access on every launch. A stable identity makes the grant stick. `DEVELOPMENT_TEAM` in project.yml |
| Attribution | **"by Apurva"**, shown once in the app's Settings/About area (Phase 3 settings window) | Keeps the notch UI itself clean, per the "feels like iOS" priority — attribution doesn't belong in the live surface |
| Island surface | **Pure black, hard-edged, every state.** Nothing may paint outside the silhouette | Two attempts broke the closed state's invisibility and were reverted (2026-09-16): an `NSVisualEffectView(.hudWindow)` material (washed grey against a bright wallpaper) and a blurred outer bleed (a blur extends *past* its shape, smearing a visible dark halo onto screen either side of the notch). A panel-wide album wash was tried in Phase 5 and cut for the same reason — it read cheap and fought the black. The album colour now appears only as a halo behind the artwork; see §2.4b |
| Space pinning | Private SkyLight space at absolute level 100 (`SkyLightPin`) | `.canJoinAllSpaces` only makes the window *present* on each desktop — it stays in the desktop layer, so a four-finger swipe drags it with the wallpaper. A space with a non-zero absolute level sits outside the desktop set like the menu bar, so desktops slide underneath. Level 100 is above every normal window but below the security agent (200) and screen lock (300). Every symbol is `dlsym`'d; if any lookup fails the app degrades to today's behaviour. Verified on macOS 26.6 — recheck each major release |
| Expanded size | 400×186 idle / 400×168 playing | Measured 15" M4 Air: screen 1710×1107pt, cutout 185×33pt at x 763…948. The cutout is missing pixels, so the island's top-centre 185×33 is invisible — all expanded content starts below it (33 + 6 clearance) instead of each column dodging it. Height is per-layout: the panel frame keeps the taller (idle) size so the change is a shape morph, never a window resize mid-hover. Music's peek is one event instead of two, so it sits shorter and the island visibly compacts when playback starts. 400 wide is ~2.2x the cutout — the wide 560 read as a banner rather than an island |
| Expanded clock/battery row | **Removed** | It cost 36pt of a 168pt island and pushed content past the shape's bottom edge onto the desktop. Time is already in the menu bar; battery lives in the compact wings |
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
| **ejbills/mediaremote-adapter** | MIT | Swift-package wrapper over the same perl-bridge technique, prebuilt binary target | What Visor actually depends on — see §7.3 |
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

- boring.notch and Atoll are **GPL-3.0**. Copying their code means Visor must also be GPL-3.0.
- DynamicNotchKit, NotchDrop, MSDisplayLink are **MIT**; mediaremote-adapter is **BSD-3**. Fine for any license, with attribution.
- **Recommendation:** license Visor **MIT**, write the code yourself, and treat GPL repos as *reading material only*. This also keeps the codebase coherent instead of a patchwork.

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

**Page swaps use it too (2026-09-23).** Turning between the three expanded
screens was a bare `.opacity` fade. That was right while each screen resolved
its own size — the shape moving under the swap was itself the feedback — and
wrong the moment every screen shared one box (§2.6b): with the shape holding
still there was nothing left to soften the change, so the new screen simply
appeared. Same `.island` transition as open and close; no new curve, no new
token.

### 2.4b Album halo (Phase 5, 2026-09-16)

A soft glow of the album's colour sits directly behind the artwork in the
expanded music layout, so the cover reads as lit from behind rather than
pasted onto a black panel.

**This was originally a wash across the whole expanded panel and was cut back
after live feedback (2026-09-16).** At panel scale a blurred cover reads as a
cheap gradient smeared over the island and fights the black surface. Confined
to the art it does the opposite, and — the point of the revision — the island
surface goes back to **pure black in every state**, which is what lets it
blend with the real hardware notch. The decision-table rule is therefore
unconditional again.

Constraints:

1. **Behind the artwork only**, sized to the cover, never to the panel.
2. **Masked by a radial gradient** so it fades to nothing well before its own
   bounds. Without that it is a blurred square with a visible edge — which is
   exactly how the panel-wide version failed.
3. **Outside the card's clip**, or the glow is cropped back into the square it
   exists to soften.
4. **Opacity ceiling 0.55** over black, with `.plusLighter` so it adds light
   rather than greying the surface.
5. **Off entirely** under Reduce Transparency or Increase Contrast.
6. **Static.** Crossfades on track change; never animates otherwise.

Blurring once per track in `ArtworkCache` rather than with SwiftUI's `.blur()`
remains load-bearing for §5.1: a live modifier re-rasterises every time the
island changes state, and the island changes state constantly.

### 2.5 Shape

- Top corners flare **outward** into the menu bar; bottom corners are rounded.
- Use **quad or cubic curves**, and make radii `animatableData` so they morph with size.
- Closed: top ≈ 6, bottom ≈ 10–14. Expanded: top ≈ 14–18, bottom ≈ 24–32.
- Consider continuous-curvature (squircle-like) bottom corners: DynamicNotchKit moved to continuous corners specifically because they read as more polished.
- **Phase 1 status (superseded):** the top edge was flush with no flare — a curve that *removes* material at the true top corner shows background through a gap right where the shape should meet the bezel.
- **Shipped 2026-09-19:** both halves of this section are now built.
  - Bottom corners are **continuous** (`UnevenRoundedRectangle(style: .continuous)`, macOS 13+, `RectangleCornerRadii` is `Animatable`). Measured against the circular arc it replaced: at r=28 the curve starts 43pt along the bottom edge instead of 28pt. The hand-rolled arc path is gone.
  - The **shoulder** is drawn as a concave quad-curve fillet per side, added as its own disjoint subpath so the fill rule unions it with the body rather than cancelling it. It *adds* material outward, which is why it never reopens the Phase 1 gap.
  - `topRadius` is **0 when closed and only there** — material outside the physical cutout would break closed-island invisibility. Compact 8, expanded 11; bottom 12/14/28.
  - The fillet tapers to zero thickness at the outer extreme by design, so a point-sample at the very corner reads as empty. Tests assert flushness across the *body* and the flare just under the top edge, not the vanishing tip.

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

### 2.6b One box for every page (2026-09-23)

The expanded island pages between three screens — agenda, player, usage —
and each used to resolve its own size. So a swipe both changed what was on
screen *and* resized the notch, which read as the island being dragged about
by a gesture that only ever meant "show me the next thing".

**Every screen the swipe can reach now resolves to one box.**
`IslandLayout.covering(_:)` grows the expanded size to hold another layout
and keeps the receiver's own wings and radii — the wings belong to the
activity, always, because they are what the island looks like at rest and a
screen you swiped to must not still be deciding them once it has closed.

The **player measures the box**, and that is a constraint on the other two
rather than an outcome:

| Screen | Extra height | Fits 160? |
| --- | --- | --- |
| Player | 160 | — it *is* the box |
| Agenda, 2 rows + overflow | 136 | yes |
| Agenda, 3 rows, no overflow | 153 | yes |
| Agenda, 3 rows + overflow | 178 | **no** |
| Agenda, 2 rows + presets | 170 | **no** |
| Usage, 2 rows | 157 | yes |

So the agenda **page** gives up two things the idle **home** screen keeps: a
third event row (`IslandLayout.maxPagedEventRows` = 2, against
`maxEventRows` = 3) and the timer presets. Both were measured, not guessed —
either one put back makes the island taller than the card it opens on, and
the player's height would then track how many meetings you have. The row the
page gives up is counted by the "+N more" line rather than lost.

Content-resolved sizing (§the island is only ever as big as its contents) is
unaffected: the box is still resolved from what `.home` is showing, so a
quiet day still gets a smaller island. What changed is that *turning a page*
is no longer a size change.

**One constant, not a conditional.** The table shows three rows *do* fit when
there is no "+N more" line under them — a day with exactly three events could
show all three. `maxPagedEventRows` is a flat 2 anyway, because a cap that
depends on whether the overflow line happens to be there is a page whose
length changes with the calendar, and the whole point of this section is that
it does not. The case it costs is narrow: exactly three upcoming events, no
more. Worth revisiting only if that turns out to be a common day.

Gated on the paging opt-in, so with the switch off nothing moved.

**Corollary bug (2026-09-23): shorter content reads as "pinned high".** The
usage screen's own alignment is inherited from the shared top-alignment the
box uses for every page. With only Claude's usage recorded (~1 row), that
screen's content is shorter than whatever page is actually driving the box
height (per the table above), so it hugged its intrinsic size at the top and
stranded empty space below — reading as the card being dragged upward rather
than centered in the box it shares. With Codex also present the content is
closer to the box height and the gap barely shows. Fixed by centering only
`.usage`'s content vertically (`NotchRootView`), not by changing the box or
the shared alignment other pages rely on.

---

## 3. Architecture

### 3.1 Module layout

```
Visor/
├── project.yml                 # XcodeGen spec
├── Visor/
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
├── VisorTests/                # geometry, activity priority, parsers
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

### 5.1b Measured regression, 2026-09-16

Idle-with-music sat at ~5% CPU. `sample` showed the main thread in
`CA::Transaction::flush_as_runloop_observer` -> `NSHostingView.layout()` every
frame: `PlaybackBars` animated `frame(height:)`, a *layout* property, so each
frame invalidated layout and re-ran the SwiftUI view graph. Rebuilt on
`CALayer` + `CABasicAnimation(transform.scale.y)`; measured A/B against the
old build on the same track: 5.2% -> 0.0%, zero frames in either hot symbol.

Two supporting fixes, same pass: `NowPlayingInfo` no longer carries playback
position (the adapter re-emits it constantly and nothing drew it, so every
tick rewrote the store and re-rendered the island), and `NotchStore.activate`
/`deactivate` plus the battery write now compare before mutating — assigning
an equal value still fires an `@Observable` notification.

**Rule this adds:** never animate a layout property in a loop. Animate
transforms, or drop to `CALayer` and let the render server own it.

### 5.1c Audit pass, 2026-09-16

A whole-codebase sweep for bugs, waste and hot paths. Four findings, all
fixed with no change to the UI or the interaction model:

1. **A 2-second polling loop in `ScreenshotService`.** `scheduleDismiss`
   re-armed on a `while` loop that woke every 2s to ask whether the island
   was still expanded — a poll, for as long as the pointer stayed on the
   island, in direct violation of rule 1. Replaced with
   `withObservationTracking` on `store.state`: the collapse itself re-arms
   the timer, and nothing runs while idle. The observation is
   self-terminating (it stops re-arming once `store.screenshot` is nil), the
   same pattern `NotchWindowController` already uses.
2. **Double-clicks were swallowed before reaching controls.**
   `NotchPanel.sendEvent` intercepts `leftMouseUp` with `clickCount == 2`
   ahead of dispatch, so a double-tap on a transport button or the
   screenshot chip's ✕ badge fired play/pause instead of the control. Now
   the intercept checks `hostingView.hitTest` first and declines anything
   over real content. `smartMagnify` still always toggles — a two-finger
   tap has no control to land on.
3. **Accessibility flags were IPC-queried from the render path.**
   `Motion.reduceMotion`, `AmbientArtBleed.isPermitted` and
   `PlaybackBars.resolvedTint` each read `NSWorkspace.accessibilityDisplay*`
   on every evaluation — inside view bodies and inside `mouseMoved`. Each
   read is a round-trip to the accessibility server. Cached in `Motion` and
   refreshed on `accessibilityDisplayOptionsDidChangeNotification`, which is
   the only event that can invalidate it.
4. **Hover parallax re-rendered the island at the mouse's event rate.**
   `mouseMoved` wrote `store.hoverPoint` on every event (~60-120/s) while
   expanded, even when nothing read it — the idle agenda and the screenshot
   chip have no tilted card. Now gated on the music card actually being on
   screen, and quantised to a 0.02 normalised step, below which the ±12°
   tilt is invisible.

**Rules these add:** an observation is cheaper than a re-check loop, even a
slow one — if you are sleeping to ask "has it changed yet", observe it
instead. And never read an accessibility or defaults flag from a view body;
cache it and refresh on its notification.

### 5.1d Collapse clipping, 2026-09-19

The island "collapsed and then rounded its corners" on every hover-out. Cause
was sequencing, not the curve. `collapseFromExpanded` resized the panel on
`completionCriteria: .logicallyComplete`; instrumenting an interpolating
`Shape` showed that criterion fires at **t=0.355s with the shape still 3.7pt
wider and 2.6pt taller than target**, which it does not reach until
**t=0.472s**. The early `setFrame` clipped the only part still protruding —
the bottom corners — so the island snapped to a hard rectangle and visibly
re-rounded inside the fixed window.

- Fix: `.removed` (callback at t=0.820s, shape settled since 0.470s). Applied
  to `exitCompact` too, whose margin was only 34ms.
- **Rule: never resize the panel on `.logicallyComplete`.** A spring is not
  visually done when it is logically done. If a discrete frame change must
  land mid-animation, the window has to be the larger of the two sizes for
  the whole transition.
- Corollary already relied on elsewhere: the canvas carries headroom
  (`NotchGeometry.squashAllowance`) so a transient overshoot cannot exceed
  its window.

Measured with a throwaway instrumented `Shape` that logs every `path(in:)`
call; the same harness disproved two other hypotheses (that stacked
`.animation(_:value:)` modifiers were eating the morph transaction, and that
per-axis scoped animations could desynchronise width from height — SwiftUI
folds both onto the ambient transaction).

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
14. **Observe, don't re-check.** A loop that sleeps in order to ask whether
    something changed is a poll no matter how long the sleep is. Use
    `withObservationTracking` and let the change wake you (§5.1c).
15. **Never read accessibility or defaults flags from a view body.** Each
    read is IPC; cache the value and refresh it on its change notification
    (§5.1c).
16. **No `NSVisualEffectView`, and no `blur()` on anything shape-shaped.** Live blur is continuously recomposited by the WindowServer, and a blur bleeds past its own silhouette — which breaks closed-state invisibility. Solid black costs nothing and can't leak.

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
| Volume changes | CoreAudio property listeners on `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (`'vmvc'`), **not** `kAudioDevicePropertyVolumeScalar` — the main-element scalar exists only where the hardware owns a master control, so reading it disabled the feature outright on Bluetooth, most USB DACs and HDMI. `'vmvc'` is the volume macOS moves and is present on every output measured; on the built-in speakers it returns the identical value the scalar did. Mute stays on `kAudioDevicePropertyMute`, which is on the main element everywhere | none |
| Brightness changes | DisplayServices (private) / observed key events | varies |
| Replace system HUD | `CGEventTap` for media keys | Accessibility |
| File shelf | SwiftUI `.onDrop` / `.draggable` | none |
| Timer | pure Swift | none |
| Launch at login | `SMAppService.mainApp` | user toggle |
| Global shortcut | **`RegisterEventHotKey` (Carbon)** — no package needed, and no permission. See §6.4 | none |

### 6.4 Measured for the command palette, 2026-09-23

Every row below was probed before any app code, from an **ad-hoc-signed
`LSUIElement` bundle launched through LaunchServices** so it carried its own
TCC identity. That last detail is the finding that matters most: the first
run of the same probe reported `AXIsProcessTrusted() == true` and was a false
pass, because a binary started from a shell inherits the *terminal's* TCC
responsibility. Launch probes with `open`, or they lie.

All of these read `AXIsProcessTrusted() == false`:

| Mechanism | Result | Used for |
|---|---|---|
| `RegisterEventHotKey` + `InstallEventHandler` | `noErr`, no prompt | ⌃⌥K. This is why the palette is cheap and a `CGEventTap` is not — the tap sees every keystroke on the machine and needs Accessibility, which is the permission the media-key HUD was cut to avoid |
| `.nonactivatingPanel` overriding `canBecomeKey` | becomes key, takes first responder, **frontmost app unchanged** | The palette types into `NotchPanel` rather than a window of its own. `canBecomeKey` is gated on the palette being open — a panel that could always take the keyboard would steal it on every brush past the notch |
| `SLSSetAppearanceThemeLegacy` / `SLSGetAppearanceThemeLegacy` (SkyLight) | resolvable; **write round-tripped** — read dark, wrote light, read back light, restored | Toggle Dark Mode. The restore ran in a `defer`, so a crash mid-probe would still have left the Mac as found |
| `SACLockScreenImmediate` (login.framework) | resolvable | Lock Screen. `dlsym`, not `@_silgen_name`: a missing symbol degrades to doing nothing instead of failing to launch |
| `kAudioHardwarePropertyDefaultOutputDevice` | settable | Switch Audio Output |
| `kAudioDevicePropertyMute`, input scope | settable on the built-in mic; **absent entirely on a Continuity iPhone microphone** | Mute Microphone, gated on the current input actually having one |

Ruled out by the same probe, each with a reason rather than a guess:

- **Empty Trash.** `~/.Trash` is not even *listable* without Full Disk
  Access — the probe got nil back for its contents. Same wall as the
  notification mirroring cut on 2026-09-16.
- **Night Shift.** `CBBlueLightClient` loads, but driving it means
  hand-declaring an ObjC interface for a headerless class to pass a
  primitive `BOOL` — the brittle binding style this codebase already
  replaced once.
- **`screencapture -i`.** Works, but a capture Visor spawns could attribute
  the Screen Recording prompt to *Visor*. Apple's Screenshot.app owns its
  own permission, and `ScreenshotService` catches whatever it writes anyway.

**Not yet taken:** the Accessibility prompt of §2 in the feature-program
spec. Nothing in Phase 6 needed it.

---

## 7. Tech stack & what to download

### 7.1 Toolchain status (as of 15 Sep 2026)

- **Xcode 26.6** is the current stable release; **Xcode 27 RC** shipped 9 Sep 2026 and **macOS 27** is about to release.
- **macOS 27 is Apple-silicon-only**, so no Intel concerns for your M4.
- **Liquid Glass** (the design language since the 26 releases) is available on macOS 26+. If you use glass materials in Visor's settings window or controls, gate with `if #available(macOS 26, *)`. The island itself stays pure black.

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
- Swipe gestures on expanded media (next/previous) — plus trackpad two-finger
  swipe and two-finger double tap (`smartMagnify`) on the panel view.
- Content layer: pure-black, hard-edged island surface (a translucent material and a
  blurred bleed were both tried and reverted — see §0).
- Calendar agenda via EventKit (**moved up from Phase 4**): `CalendarService`,
  full-agenda idle-expanded layout, 1-event peek in the music-expanded split
  (2 was what forced the island to stay tall while playing).
- ~~Mood/genre chip bar docked under the expanded island while playing~~ — removed 2026-09-16: stub actions that did nothing, and its canvas reserve made the hosting view taller than the island, which pushed the whole island 22pt below the notch.
- Expanded size: settled at 400×186 idle / 400×168 playing (see §0). 600×220 and 560-wide were both tried and read as a banner rather than an island.
- Fullscreen handling, sleep/wake, multi-display, settings window, launch at login.
- Playback bars on the artwork and in the compact wing — decorative, not a
  spectrum analyser (macOS exposes no other app's audio). Core Animation runs
  the loop on the render server, and it exists only while playing.
- Settings/About area shows "by Apurva" once (see §0 Attribution). Power rules
  (§5.2) still apply here: nothing in that window may animate or tick while
  the settings window is closed.

### Phase 4 — Features
- **Drop target (done 2026-09-16):** dragging an image onto the island opens it
  (`isDropTargeted` observed by the window controller) and adopts the file as the
  current catch. The highlight is the shape's own outline stroked and clipped back to
  itself — nothing paints outside the silhouette.
- **Screenshot catcher (done 2026-09-16):** `DispatchSource` on the folder from
  `com.apple.screencapture location` — event-driven, no timer. New images become a
  `ScreenshotCatch` shown as a chip in the compact wing, draggable out, click to open,
  auto-dismissed after 60s with the countdown re-armed while the island is open, or instantly via an iOS-style dismiss badge.
- **Album tint (done 2026-09-16):** the playback bars take the cover's colour, the way
  iOS tints its waveform. The island *surface* is never tinted — that is what Apple
  avoids and what this project reverted a material and a blurred bleed to protect.
  OKLab + fixed-seed k-means, chroma floor 0.045 (greyscale covers get white bars),
  lightness lifted to 0.78 so contrast on black never depends on the album.
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
