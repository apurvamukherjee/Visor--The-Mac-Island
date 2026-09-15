# Visor Phase 3 — Content Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Git:** NEVER commit. Stage nothing automatically. The user commits by hand, at whatever granularity they choose. Stop at the end of each task and wait for review instead of running `git commit`. This overrides the writing-plans skill's default "commit" step — it is a standing project rule (CLAUDE.md).

**Goal:** Replace Phase 2's placeholder expanded content with the real UI layer — a translucent material surface, an EventKit-backed calendar agenda, a split music+calendar expanded layout, a play-state-gated mood chip bar, and the micro-animations that make the island read as fluid.

**Architecture:** One `NotchShape` still morphs between three states; only its *fill* gains a material layer (an `NSVisualEffectView` masked to the shape, under a black overlay whose opacity animates with state, so closed stays pure black and hardware-invisible). A new `CalendarService: NotchService` pushes `[CalendarEvent]` into `NotchStore`, event-driven via `.EKEventStoreChanged`. `NotchRootView`'s expanded branch splits into `ExpandedIdleView` (full agenda) and `ExpandedMusicView` (split music + 2-event peek), both sharing one `EventRow`. The expanded frame grows to 600×220 with vertical room reserved for a detached `MoodChipBar`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, AppKit (`NSVisualEffectView`, `NSWorkspace`) confined to `Window/`, EventKit, Swift Testing (`@Test`/`#expect`).

**Spec:** `docs/superpowers/specs/2026-09-16-notch-content-layer-design.md`

## Global Constraints

- Swift 6 language mode, strict concurrency complete (`project.yml` already sets this).
- macOS 14.0 minimum, Apple silicon.
- SwiftUI for all views; AppKit only in `Window/` and `App/`.
- XcodeGen: edit `project.yml`, never `.pbxproj`; run `xcodegen generate` after changes.
- No third-party Swift packages without the user's explicit approval.
- No force unwraps, no `try!`, no `print()` — `os.Logger` via `Log.swift` only.
- Event-driven only. No polling loops, no global mouse monitors, no ticking timers. Nothing animates or ticks when not visible, not playing, or display asleep.
- All animation durations/curves come from `Motion` tokens. Every `withAnimation` wraps its token in `Motion.resolved(_:)` for Reduce Motion. No raw `.spring`/`.easeInOut` in view code.
- One `NotchShape` — never cross-fade two shapes. Shape leads, content follows.
- A feature never imports another feature. Cross-feature composition lives in `UI/`.
- Unit-test pure logic only (geometry, parsers, mappers) — no UI tests, matching the existing suite.
- Run build, tests, `swiftformat .`, and `swiftlint` before calling a task done.
- Comments explain *why*, not *what*. No commented-out code, no TODOs without an issue reference.

**Verified SDK facts (checked against MacOSX27.0.sdk on 2026-09-16 — do not re-derive):**
- `requestFullAccessToEventsWithCompletion:` is `API_AVAILABLE(macos(14.0))`. Swift async spelling: `try await store.requestFullAccessToEvents()`.
- `requestAccessToEntityType:completion:` is **deprecated** as of macOS 14.0 — do not use it.
- `EKAuthorizationStatus` cases on macOS 14+: `.notDetermined`, `.restricted`, `.denied`, `.fullAccess`, `.writeOnly`. `.authorized` is deprecated (aliases `.fullAccess`).
- `EKEventStoreChangedNotification` exists since macOS 10.8. Swift: `.EKEventStoreChanged`.
- Xcode recognizes all three plist keys: `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, and legacy `NSCalendarsUsageDescription`. **Full read access requires `NSCalendarsFullAccessUsageDescription`.**

---

### Task 1: Geometry — expanded size growth + chip-bar reservation

**Files:**
- Modify: `Visor/Window/NotchGeometry.swift`
- Test: `VisorTests/NotchGeometryTests.swift`

**Interfaces:**
- Consumes: existing `ScreenGeometryProviding`, `closedRect(for:)`, `compactRect(for:)`, `expandedRect(for:)`.
- Produces: `NotchGeometry.chipBarHeight: CGFloat`, `NotchGeometry.chipBarGap: CGFloat`, changed `NotchGeometry.expandedSize`, changed `NotchGeometry.expandedCanvasRect(for:)` behaviour.

- [ ] **Step 1: Write the failing test**

Add to `VisorTests/NotchGeometryTests.swift` (reuses the existing private `FakeScreen`):

```swift
    @Test
    func expandedCanvasReservesRoomForTheChipBarBelowTheIsland() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
        )

        let expanded = NotchGeometry.expandedRect(for: screen)
        let canvas = NotchGeometry.expandedCanvasRect(for: screen)

        // Canvas must be at least as wide as both expanded and compact...
        #expect(canvas.width >= expanded.width)
        #expect(canvas.width >= NotchGeometry.compactRect(for: screen).width)
        // ...and taller than the island by exactly the chip bar's gap + height,
        // so the chip bar animates in inside an already-large-enough frame.
        #expect(canvas.height == expanded.height + NotchGeometry.chipBarGap + NotchGeometry.chipBarHeight)
        // Canvas shares the island's top edge — it only grows downward.
        #expect(canvas.maxY == expanded.maxY)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: build fails — `chipBarHeight` and `chipBarGap` don't exist.

- [ ] **Step 3: Implement**

In `Visor/Window/NotchGeometry.swift`, change the existing `expandedSize` constant and add the two new ones:

```swift
    static let expandedSize = CGSize(width: 600, height: 220)
    static let chipBarHeight: CGFloat = 36
    static let chipBarGap: CGFloat = 8
```

Replace the existing `expandedCanvasRect(for:)` with:

```swift
    /// `expandedRect` widened to also contain `compactRect`, then extended
    /// downward to reserve the mood chip bar's strip. The panel is
    /// click-through outside the shape, so an over-tall canvas costs nothing
    /// visually — and it means neither collapsing out of expanded nor the
    /// chip bar animating in ever has to grow the frame mid-animation, which
    /// is what caused the expanded→compact jitter bug.
    static func expandedCanvasRect(for screen: ScreenGeometryProviding) -> CGRect {
        let union = expandedRect(for: screen).union(compactRect(for: screen))
        return CGRect(
            x: union.minX,
            y: union.minY - chipBarGap - chipBarHeight,
            width: union.width,
            height: union.height + chipBarGap + chipBarHeight
        )
    }
```

*Note for the implementer:* `NotchGeometry` works in a bottom-left origin (AppKit screen) coordinate space — `closedRect` is built as `screen.frame.maxY - height`. Growing "downward" therefore means **lowering `minY`** while keeping `maxY` fixed, which is what the code above does. Trust the test's `canvas.maxY == expanded.maxY` assertion over any intuition about which direction is "down".

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: all tests pass, including the existing `expandedRectSharesClosedRectHorizontalCenterAndTopEdge` and `compactRectSharesClosedRectTopEdgeAndCenterAndAddsWingWidth` (both unchanged in behaviour).

- [ ] **Step 5: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing `trailing_comma` warnings in `VisorTests/ActivityTests.swift`, `VisorTests/BatteryInfoParserTests.swift`, and `Visor/Features/NowPlaying/ArtworkCache.swift` — a repo-wide swiftformat/swiftlint config disagreement that predates this plan. Do not "fix" them.

---

### Task 2: Motion tokens for the content layer

**Files:**
- Modify: `Visor/Core/Motion.swift`

**Interfaces:**
- Produces: `Motion.layout`, `Motion.artSwap`, `Motion.textSwap`, `Motion.chipBarIn`, `Motion.chipBarOut`.

No test — `Motion` is a table of constants, matching how the existing `open`/`close`/`morph`/`contentIn`/`contentOut` tokens carry no tests.

- [ ] **Step 1: Add the five tokens**

In `Visor/Core/Motion.swift`, add inside `enum Motion`, after the existing `contentOut`:

```swift
    /// idle ↔ music expanded column redistribution — one coordinated layout
    /// change, not two sequential ones
    static let layout = Animation.spring(duration: 0.40, bounce: 0.18)
    /// album art crossfade + scale-pop on track change
    static let artSwap = Animation.spring(duration: 0.30, bounce: 0.20)
    /// title/artist crossfade — opacity only, text never transforms
    static let textSwap = Animation.easeInOut(duration: 0.15)
    /// chip bar entrance, staggered to arrive after the play-state settles
    static let chipBarIn = Animation.spring(duration: 0.40, bounce: 0.22).delay(0.12)
    /// chip bar exit — a reverse of the entrance, never a plain fade-out
    static let chipBarOut = Animation.spring(duration: 0.28, bounce: 0.0)
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean. The tokens are unreferenced until Tasks 5–8; that is expected mid-plan.

- [ ] **Step 3: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings (see Task 1 Step 5).

---

### Task 3: Accessibility flags — Reduce Transparency observation

**Files:**
- Create: `Visor/Support/Accessibility.swift`
- Modify: `Visor/Core/NotchStore.swift`

**Interfaces:**
- Consumes: `NotchStore` (existing `@Observable @MainActor` class).
- Produces: `final class AccessibilityObserver` with `init(store:)`, `func start()`, `func stop()`; `NotchStore.reduceTransparency: Bool` (read-only), `NotchStore.setReduceTransparency(_:)`.

`Motion.resolved(_:)` already handles Reduce Motion by reading `NSWorkspace` at call time, so this task covers only Reduce **Transparency**, which the material layer (Task 4) needs to read during rendering.

- [ ] **Step 1: Extend `NotchStore`**

Add to `Visor/Core/NotchStore.swift`, inside the existing `NotchStore` class, alongside the other `private(set)` properties:

```swift
    private(set) var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
```

and alongside the other setters:

```swift
    func setReduceTransparency(_ reduce: Bool) {
        reduceTransparency = reduce
    }
```

Add `import AppKit` to the top of `NotchStore.swift` if it isn't already there (the file currently imports `CoreGraphics`, `Foundation`, `Observation`).

- [ ] **Step 2: Implement `AccessibilityObserver`**

```swift
// Visor/Support/Accessibility.swift
import AppKit

/// Mirrors the system's Reduce Transparency setting into the store so views
/// can read it as observable state. Reduce *Motion* needs no equivalent —
/// `Motion.resolved(_:)` reads it at call time, when an animation is built.
@MainActor
final class AccessibilityObserver {
    private let store: NotchStore
    private var observer: NSObjectProtocol?

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        sync()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func sync() {
        store.setReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}
```

*Note for the implementer:* this deliberately does **not** conform to `NotchService`. That protocol is the contract for *feature data sources* (`Features/<Name>/`); this is a `Support/` utility mirroring a system setting. Wire it in Task 9 the same way services are, but keep it out of the protocol.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean. Unreferenced until Task 9.

- [ ] **Step 4: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 4: Material layer — `NSVisualEffectView` behind the shape

**Files:**
- Create: `Visor/Window/VisualEffectBackground.swift`
- Modify: `Visor/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `NotchShape`, `NotchStore.state`, `NotchStore.reduceTransparency` (Task 3).
- Produces: `struct VisualEffectBackground: NSViewRepresentable` (no parameters).

No unit test — this is AppKit-bridged rendering, matching the project's no-UI-tests convention. Covered by Task 11's manual checklist.

- [ ] **Step 1: Implement `VisualEffectBackground`**

```swift
// Visor/Window/VisualEffectBackground.swift
import AppKit
import SwiftUI

/// `.hudWindow` over `.underWindowBackground`: the latter is semantically
/// "the material shown *under* a window's background" and reads washed out
/// when floated as the top surface. `.hudWindow` is the match for a small
/// translucent panel over arbitrary content, which is what the island is.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
```

- [ ] **Step 2: Layer it into `NotchRootView`**

In `Visor/UI/NotchRootView.swift`, replace the existing `NotchShape(...).fill(.black)` line — currently the first line of `body` — with a layered background. Add these two computed properties to `NotchRootView`:

```swift
    private var shape: NotchShape {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
    }

    /// 1.0 at closed keeps the island pure black so it stays invisible
    /// against the hardware notch (a Phase 1 acceptance criterion); the
    /// material only reads through once the shape has grown past the real
    /// cutout. Reduce Transparency pins it opaque in every state.
    private var blackOverlayOpacity: Double {
        if store.reduceTransparency { return 1 }
        switch store.state {
        case .closed: return 1
        case .compact: return 0.55
        case .expanded: return 0.15
        }
    }
```

and replace the `body`'s first two lines:

```swift
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(.black)
```

with:

```swift
        islandSurface
```

then add `islandSurface` as a computed property:

```swift
    private var islandSurface: some View {
        ZStack {
            if !store.reduceTransparency {
                // Soft outer bleed so the edge doesn't hard-cut against the
                // wallpaper. Behind everything, low opacity, blurred.
                shape
                    .fill(.black)
                    .blur(radius: 8)
                    .opacity(0.35)
                VisualEffectBackground()
                    .clipShape(shape)
            }
            shape
                .fill(.black)
                .opacity(blackOverlayOpacity)
        }
    }
```

*Note for the implementer:* keep the existing `.frame(width:height:)`, `.overlay(alignment: .top)`, and outer `.frame(...)` modifiers exactly as they are, chained onto `islandSurface` instead of onto the old `NotchShape(...).fill(.black)`. Only the fill is changing — the shape, its radii, and the content overlay are untouched.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean.

- [ ] **Step 4: Run tests**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: all existing tests still pass (no test surface touched).

- [ ] **Step 5: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 5: `CalendarEvent` model + `CalendarEventMapper` (pure logic)

**Files:**
- Create: `Visor/Features/Calendar/CalendarEvent.swift`
- Create: `Visor/Features/Calendar/CalendarEventMapper.swift`
- Test: `VisorTests/CalendarEventMapperTests.swift`

**Interfaces:**
- Produces: `struct CalendarEvent: Equatable, Identifiable, Sendable` with `id: String`, `title: String`, `start: Date`, `end: Date`, `isAllDay: Bool`, `colorHex: String?`; `enum CalendarEventMapper` with `static func upcoming(_ events: [CalendarEvent], now: Date, limit: Int) -> [CalendarEvent]` and `static func overflowCount(total: Int, shown: Int) -> Int`.

This task deliberately keeps `EKEvent` out of the pure layer — the mapper operates on already-built `CalendarEvent` values so it is testable without an `EKEventStore`. `EKEvent → CalendarEvent` conversion lives in `CalendarService` (Task 6), which has no unit tests, matching how `BatteryService` carries the IOKit bridging while `BatteryInfoParser` carries the tested logic.

- [ ] **Step 1: Write the failing tests**

```swift
// VisorTests/CalendarEventMapperTests.swift
import Foundation
import Testing
@testable import Visor

struct CalendarEventMapperTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func event(
        id: String,
        startOffset: TimeInterval,
        duration: TimeInterval = 3600,
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Event \(id)",
            start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + duration),
            isAllDay: isAllDay,
            colorHex: nil
        )
    }

    @Test
    func upcomingDropsEventsThatHaveAlreadyEnded() {
        let events = [
            Self.event(id: "past", startOffset: -7200),
            Self.event(id: "future", startOffset: 3600)
        ]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 10)
        #expect(result.map(\.id) == ["future"])
    }

    @Test
    func upcomingKeepsAnEventThatIsCurrentlyInProgress() {
        // Started an hour ago, ends an hour from now — still relevant.
        let events = [Self.event(id: "ongoing", startOffset: -3600, duration: 7200)]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 10)
        #expect(result.map(\.id) == ["ongoing"])
    }

    @Test
    func upcomingSortsByStartAndAppliesTheLimit() {
        let events = [
            Self.event(id: "third", startOffset: 10800),
            Self.event(id: "first", startOffset: 600),
            Self.event(id: "second", startOffset: 3600)
        ]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 2)
        #expect(result.map(\.id) == ["first", "second"])
    }

    @Test
    func upcomingKeepsAllDayEventsForTheWholeDay() {
        let events = [Self.event(id: "allday", startOffset: -3600, duration: 86400, isAllDay: true)]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 10)
        #expect(result.map(\.id) == ["allday"])
    }

    @Test
    func overflowCountIsZeroWhenEverythingIsShown() {
        #expect(CalendarEventMapper.overflowCount(total: 3, shown: 4) == 0)
        #expect(CalendarEventMapper.overflowCount(total: 4, shown: 4) == 0)
    }

    @Test
    func overflowCountReportsTheRemainder() {
        #expect(CalendarEventMapper.overflowCount(total: 7, shown: 4) == 3)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: build fails — `CalendarEvent` and `CalendarEventMapper` don't exist.

- [ ] **Step 3: Implement `CalendarEvent`**

```swift
// Visor/Features/Calendar/CalendarEvent.swift
import Foundation

/// A calendar entry, decoupled from EventKit so the list logic stays pure
/// and testable without an `EKEventStore`.
struct CalendarEvent: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// `EKCalendar`'s colour, as a hex string — keeps this model free of
    /// AppKit/SwiftUI so it can live in tests and services alike.
    let colorHex: String?
}
```

- [ ] **Step 4: Implement `CalendarEventMapper`**

```swift
// Visor/Features/Calendar/CalendarEventMapper.swift
import Foundation

enum CalendarEventMapper {
    /// Events still worth showing, soonest first. An event counts as
    /// upcoming until it has actually *ended*, so something in progress
    /// right now doesn't vanish from the agenda halfway through.
    static func upcoming(_ events: [CalendarEvent], now: Date, limit: Int) -> [CalendarEvent] {
        events
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    static func overflowCount(total: Int, shown: Int) -> Int {
        max(0, total - shown)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: all six new tests pass, plus the existing suite.

- [ ] **Step 6: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 6: `CalendarService` — EventKit, event-driven

**Files:**
- Create: `Visor/Features/Calendar/CalendarService.swift`
- Modify: `Visor/Core/NotchStore.swift`
- Modify: `Visor/Support/Log.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `NotchService` protocol, `CalendarEvent` (Task 5), `NotchStore`.
- Produces: `final class CalendarService: NotchService`; `NotchStore.calendarEvents: [CalendarEvent]` (read-only), `NotchStore.setCalendarEvents(_:)`; `Log.calendar`.

Calendar is deliberately **not** an `ActivityKind` — it is ambient context for the expanded state, never a claimant on the compact state.

- [ ] **Step 1: Add a `calendar` logging category**

In `Visor/Support/Log.swift`, add alongside the existing `app`/`window`/`battery`/`nowPlaying` categories:

```swift
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
```

- [ ] **Step 2: Extend `NotchStore`**

Add to `Visor/Core/NotchStore.swift`, inside the existing class:

```swift
    private(set) var calendarEvents: [CalendarEvent] = []

    func setCalendarEvents(_ events: [CalendarEvent]) {
        calendarEvents = events
    }
```

- [ ] **Step 3: Add the usage-description key to `project.yml`**

In `project.yml`, under `targets: Visor: info: properties:`, add alongside the existing `LSUIElement` and `NSHumanReadableCopyright`:

```yaml
        NSCalendarsFullAccessUsageDescription: "Visor shows your upcoming events in the notch."
```

`NSCalendarsFullAccessUsageDescription` is the key required for read access on macOS 14+ (verified against MacOSX27.0.sdk — see Global Constraints). The legacy `NSCalendarsUsageDescription` is not needed since the deployment target is 14.0.

Then run: `xcodegen generate`

- [ ] **Step 4: Implement `CalendarService`**

```swift
// Visor/Features/Calendar/CalendarService.swift
import AppKit
import EventKit

@MainActor
final class CalendarService: NotchService {
    private let store: NotchStore
    private let eventStore = EKEventStore()
    private var observer: NSObjectProtocol?
    private var hasAccess = false

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task { await requestAccessAndRefresh() }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        store.setCalendarEvents([])
    }

    private func requestAccessAndRefresh() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            hasAccess = true
        case .notDetermined:
            do {
                hasAccess = try await eventStore.requestFullAccessToEvents()
            } catch {
                Log.calendar.error("Calendar access request failed: \(error.localizedDescription)")
                hasAccess = false
            }
        case .denied, .restricted, .writeOnly:
            // Write-only can't read events, so it's a denial for our purposes.
            Log.calendar.info("Calendar access unavailable; the agenda stays empty.")
            hasAccess = false
        @unknown default:
            hasAccess = false
        }
        refresh()
    }

    private func refresh() {
        guard hasAccess else {
            store.setCalendarEvents([])
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            Log.calendar.error("Could not compute today's end date.")
            return
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).map(Self.convert)
        store.setCalendarEvents(events)
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            colorHex: event.calendar?.color.map(Self.hex)
        )
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

*Notes for the implementer:*
- `EKEventStore.authorizationStatus(for:)` is the Swift spelling of `authorizationStatusForEntityType:`. Do **not** call the deprecated `requestAccessToEntityType:completion:`.
- `event.calendar` and `event.eventIdentifier` are nullable in the ObjC headers even though Swift may surface them as non-optional in some SDK versions. If the compiler rejects `event.calendar?.color` or `event.eventIdentifier ?? ...` as a redundant optional operation, drop the optionality to match what the compiler reports — trust the compiler over this snippet, and do not force-unwrap either way.
- `refresh()` is called from the `.EKEventStoreChanged` observer only. No timer, no polling — that is the non-negotiable power rule.

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean. `CalendarService` is unreferenced until Task 9; that's expected mid-plan.

- [ ] **Step 6: Run tests**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: Task 5's mapper tests plus the existing suite all pass.

- [ ] **Step 7: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 7: `EventRow` — the shared agenda row

**Files:**
- Create: `Visor/UI/EventRow.swift`

**Interfaces:**
- Consumes: `CalendarEvent` (Task 5).
- Produces: `struct EventRow: View` with `init(event: CalendarEvent)`.

**One implementation, used by both expanded layouts.** Forking this styling between idle and music-live is explicitly out of bounds — only the *container* layout differs.

Lives in `UI/`, not `Features/Calendar/`, because Task 9's `ExpandedMusicView` composes it alongside Now Playing content, and a feature may never import another feature.

- [ ] **Step 1: Implement `EventRow`**

```swift
// Visor/UI/EventRow.swift
import SwiftUI

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
    }

    private var barColor: Color {
        event.colorHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var timeLabel: String {
        event.isAllDay
            ? "All day"
            : event.start.formatted(date: .omitted, time: .shortened)
    }
}

extension Color {
    /// `#RRGGBB` only — the single format `CalendarService` emits.
    init?(hex: String) {
        var value = UInt64.zero
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else {
            return nil
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean. Unreferenced until Task 8.

- [ ] **Step 3: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 8: `ExpandedIdleView`, `ExpandedMusicView`, `MoodChipBar`

**Files:**
- Create: `Visor/UI/ExpandedIdleView.swift`
- Create: `Visor/UI/ExpandedMusicView.swift`
- Create: `Visor/UI/MoodChipBar.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarEventMapper` (Task 5), `EventRow` (Task 7), `NowPlayingInfo`, `NotchStore.NowPlayingCommands` (Phase 2), `Motion.artSwap`/`textSwap`/`chipBarIn`/`chipBarOut` (Task 2), `NotchGeometry.chipBarHeight`/`chipBarGap` (Task 1).
- Produces: `ExpandedIdleView(events:signature:)`, `ExpandedMusicView(info:artwork:commands:events:)`, `MoodChipBar()`.

No unit tests — pure SwiftUI layout, matching the project convention. Covered by Task 11's manual checklist.

- [ ] **Step 1: Implement `ExpandedIdleView`**

Per the spec's §8 default, the "By Apurva" signature is **kept**, living beside the date header rather than being deleted.

```swift
// Visor/UI/ExpandedIdleView.swift
import SwiftUI

/// Expanded, nothing playing: the day's full agenda in two columns.
struct ExpandedIdleView: View {
    let events: [CalendarEvent]

    private static let shownLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if shown.isEmpty {
                Text("Nothing scheduled")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                columns
            }
            if overflow > 0 {
                Text("+\(overflow) more event\(overflow == 1 ? "" : "s")")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var shown: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.shownLimit)
    }

    private var overflow: Int {
        CalendarEventMapper.overflowCount(total: events.count, shown: shown.count)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date.now, format: .dateTime.weekday(.abbreviated).day())
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            SignatureGlow()
        }
    }

    private var columns: some View {
        let half = (shown.count + 1) / 2
        return HStack(alignment: .top, spacing: 12) {
            column(Array(shown.prefix(half)))
            column(Array(shown.dropFirst(half)))
        }
    }

    private func column(_ events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(events) { EventRow(event: $0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

*Note for the implementer:* `SignatureGlow` currently lives as a `private struct` at the bottom of `Visor/UI/NotchRootView.swift`. Move it into its own file `Visor/UI/SignatureGlow.swift` and drop the `private` so both files can use it. Keep its body, `@State`, maroon colour, `.title3`/`.semibold` font, and `Motion.pulse` usage byte-for-byte as they are — the user tuned that deliberately.

- [ ] **Step 2: Implement `MoodChipBar`**

```swift
// Visor/UI/MoodChipBar.swift
import SwiftUI

/// Docked under the expanded island while playback is active. Selection is
/// a stub — tapping logs and nothing else, per the Phase 3 spec.
struct MoodChipBar: View {
    @State private var selected: String?

    private static let moods = ["Party", "Feel good", "Relax", "Sleep", "Work out", "Commute"]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Self.moods, id: \.self) { mood in
                    chip(mood)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.never)
        .frame(height: NotchGeometry.chipBarHeight)
    }

    private func chip(_ mood: String) -> some View {
        let isSelected = selected == mood
        return Button {
            selected = mood
            Log.app.info("Mood chip selected: \(mood, privacy: .public)")
        } label: {
            Text(mood)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(isSelected ? .white : .white.opacity(0.12))
                }
                .overlay {
                    Capsule().stroke(.white.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Implement `ExpandedMusicView`**

```swift
// Visor/UI/ExpandedMusicView.swift
import SwiftUI

/// Expanded with something playing: music on the left, a trimmed calendar
/// peek on the right. The calendar shrinks to make room — it never
/// disappears.
struct ExpandedMusicView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let commands: NotchStore.NowPlayingCommands?
    let events: [CalendarEvent]

    private static let peekLimit = 2
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            musicColumn
            Divider().overlay(.white.opacity(0.15))
            calendarColumn
        }
        .foregroundStyle(.white)
    }

    private var musicColumn: some View {
        HStack(spacing: 10) {
            artworkView
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .lineLimit(1)
                if let artist = info.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                controls.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        // Text crossfades on track change; it never flips or rotates.
        .id(info.trackIdentity)
        .transition(.opacity.animation(Motion.resolved(Motion.textSwap)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    /// Threshold swipe only — no live drag tracking, no velocity handling.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard abs(value.translation.width) > Self.swipeThreshold else { return }
                if value.translation.width < 0 {
                    commands?.next()
                } else {
                    commands?.previous()
                }
            }
    }

    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.15))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Crossfade + scale-pop, not a 3D flip: at this size a Y-axis flip's
        // foreshortened mid-frames span a handful of pixels and read as a
        // flicker. See the spec's §9.2.
        .id(info.trackIdentity)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                removal: .opacity
            )
            .animation(Motion.resolved(Motion.artSwap))
        )
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { commands?.previous() } label: { Image(systemName: "backward.fill") }
            Button { commands?.togglePlayPause() } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            Button { commands?.next() } label: { Image(systemName: "forward.fill") }
        }
        .font(.caption)
        .buttonStyle(.plain)
    }

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(peek) { EventRow(event: $0) }
            Spacer(minLength: 0)
        }
        .frame(width: 200, alignment: .leading)
    }

    private var peek: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.peekLimit)
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean. These views are unreferenced until Task 9.

- [ ] **Step 5: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 9: Wire it together — `NotchRootView` routing, chip-bar docking, hit-test union, app wiring

**Files:**
- Modify: `Visor/UI/NotchRootView.swift`
- Create: `Visor/UI/SignatureGlow.swift` (moved out of `NotchRootView.swift` — see Task 8 Step 1)
- Modify: `Visor/Window/NotchContentView.swift`
- Modify: `Visor/App/AppDelegate.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: a fully wired app.

- [ ] **Step 1: Route the expanded branch in `NotchRootView`**

Replace `NotchRootView`'s `expandedContent` (and the `topRow` helper it uses) with:

```swift
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // topRow's height matches store.closedSize.height (the real
            // hardware safe area) so Clock/Battery flank the camera housing
            // instead of sitting below a blank gap the width of the whole
            // shape.
            topRow
                .frame(height: store.closedSize.height)
            if let info = store.nowPlaying {
                ExpandedMusicView(
                    info: info,
                    artwork: store.nowPlayingArtwork,
                    commands: store.nowPlayingCommands,
                    events: store.calendarEvents
                )
            } else {
                ExpandedIdleView(events: store.calendarEvents)
            }
        }
        .padding(.horizontal, 12)
    }

    private var topRow: some View {
        HStack {
            ClockPlaceholderView()
            Spacer(minLength: 0)
            if let battery = store.battery {
                ExpandedBatteryRow(info: battery)
            }
        }
    }
```

Per the spec's §8 default, `ClockPlaceholderView` and `ExpandedBatteryRow` are **kept**, not deleted.

- [ ] **Step 2: Dock the chip bar below the island**

In `NotchRootView`'s `body`, the existing outer `.frame(width:height:alignment:)` currently sizes to `NotchGeometry.expandedSize.height`. Wrap the island and the chip bar in a `VStack` so the bar docks under the shape with a gap, inside the already-reserved canvas from Task 1.

Replace the `body`'s final `.frame(...)` line with:

```swift
            .overlay(alignment: .bottom) { chipBarDock }
            .frame(width: canvasWidth, height: NotchGeometry.expandedSize.height, alignment: .top)
```

and add:

```swift
    private var showChipBar: Bool {
        store.state == .expanded && store.nowPlaying?.isPlaying == true
    }

    @ViewBuilder
    private var chipBarDock: some View {
        if showChipBar {
            MoodChipBar()
                .offset(y: NotchGeometry.chipBarHeight + NotchGeometry.chipBarGap)
                .transition(
                    .move(edge: .top)
                        .combined(with: .opacity)
                        .animation(Motion.resolved(Motion.chipBarIn))
                )
        }
    }
```

*Note for the implementer:* the asymmetric in/out curves (`Motion.chipBarIn` on entry, `Motion.chipBarOut` on exit) are best expressed with `.asymmetric(insertion:removal:)` if the single-animation form above doesn't produce a distinct exit. Exit must be a reverse of the entrance — a slide-down plus fade — never a plain fade-out. Verify by eye in Task 11.

- [ ] **Step 3: Animate the idle ↔ music layout change**

The calendar column compressing and the music column growing must be **one** coordinated animation, not two. Add to `NotchRootView`'s `body`, chained after the outer `.frame(...)`:

```swift
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying?.trackIdentity)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying == nil)
```

- [ ] **Step 4: Extend `hitTest` with the chip-bar rect**

In `Visor/Window/NotchContentView.swift`, replace the body of `hitTest(_:)`:

```swift
    /// Click-through outside the shape's silhouette. Tested against the
    /// current state's target radii, not interpolated live geometry — an
    /// accepted approximation (ponytail: lags the visual shape during the
    /// ~300-400ms animation window; upgrade to interpolated radii if that
    /// sliver ever matters in practice).
    ///
    /// The mood chip bar is docked *below* the shape with a gap, so it falls
    /// outside that silhouette — without the union below, the chips would
    /// render but be unclickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        let (topRadius, bottomRadius): (CGFloat, CGFloat) = switch store.state {
        case .expanded: (NotchShape.expandedTopRadius, NotchShape.expandedBottomRadius)
        case .compact: (NotchShape.compactTopRadius, NotchShape.compactBottomRadius)
        case .closed: (NotchShape.closedTopRadius, NotchShape.closedBottomRadius)
        }
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        let islandRect = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: NotchGeometry.expandedSize.height
        )
        if shape.path(in: islandRect).contains(local) {
            return super.hitTest(point)
        }
        if chipBarIsVisible, chipBarRect.contains(local) {
            return super.hitTest(point)
        }
        return nil
    }

    private var chipBarIsVisible: Bool {
        store.state == .expanded && store.nowPlaying?.isPlaying == true
    }

    private var chipBarRect: CGRect {
        CGRect(
            x: 0,
            y: NotchGeometry.expandedSize.height + NotchGeometry.chipBarGap,
            width: bounds.width,
            height: NotchGeometry.chipBarHeight
        )
    }
```

*Note for the implementer:* `NotchContentView` has `isFlipped == true`, so its local origin is top-left and y grows downward — the chip-bar rect therefore sits at a *larger* y than the island, as written above. This is the opposite convention from `NotchGeometry` (bottom-left, AppKit screen space) in Task 1; don't let the two confuse each other.

- [ ] **Step 4a: Verify the hit-test change against the shape path**

The island's shape path must be built against the island's own rect, not the full (chip-bar-inclusive) `bounds` — otherwise the shape stretches to fill the taller canvas and the silhouette is wrong. Confirm by reading the code that `shape.path(in: islandRect)` is used, never `shape.path(in: bounds)`.

- [ ] **Step 5: Wire the new services into `AppDelegate`**

```swift
// Visor/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?
    private var batteryService: BatteryService?
    private var nowPlayingService: NowPlayingService?
    private var calendarService: CalendarService?
    private var accessibilityObserver: AccessibilityObserver?

    func applicationDidFinishLaunching(_: Notification) {
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Visor cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        windowController = controller
        controller.start()

        let accessibility = AccessibilityObserver(store: store)
        accessibility.start()
        accessibilityObserver = accessibility

        let battery = BatteryService(store: store)
        battery.start()
        batteryService = battery

        let nowPlaying = NowPlayingService(store: store)
        nowPlaying.start()
        nowPlayingService = nowPlaying

        let calendar = CalendarService(store: store)
        calendar.start()
        calendarService = calendar
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.stop()
        batteryService?.stop()
        nowPlayingService?.stop()
        calendarService?.stop()
        accessibilityObserver?.stop()
    }
}
```

- [ ] **Step 6: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: builds clean.

- [ ] **Step 7: Run tests**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: everything passes — `CalendarEventMapperTests`, `ActivityTests`, `BatteryInfoParserTests`, `NowPlayingInfoTests`, `NotchGeometryTests`, `NotchShapeTests`, `NotchStoreTests`.

- [ ] **Step 8: Format, lint, and stop for review**

Run: `swiftformat . && swiftlint`
Expected: clean apart from the 7 known pre-existing warnings.

---

### Task 10: Update `docs/RESEARCH.md`

**Files:**
- Modify: `docs/RESEARCH.md`

**Interfaces:** None — documentation only.

RESEARCH.md is the project's stated source of truth, and this plan changed decisions recorded there as settled. Leaving it stale makes it actively misleading.

- [ ] **Step 1: Update §8 Phase 3**

Replace the Phase 3 bullet list's first two lines:

```
- Numeric text transitions, symbol effects, haptics, Reduce Motion.
- Swipe gestures on expanded media (next/previous).
```

with:

```
- Numeric text transitions, symbol effects, haptics, Reduce Motion.
- Swipe gestures on expanded media (next/previous).
- Content layer: `NSVisualEffectView(.hudWindow)` material behind the shape with a
  state-driven black overlay (closed stays pure black), soft edge bleed, and a
  Reduce Transparency fallback to solid fill.
- Calendar agenda via EventKit (**moved up from Phase 4**): `CalendarService`,
  full-agenda idle-expanded layout, 2-event peek in the music-expanded split.
- Mood/genre chip bar docked under the expanded island while playing (stub actions).
- Expanded size grows to 600×220 to fit the two-column agenda.
```

- [ ] **Step 2: Update §8 Phase 4**

Replace:

```
- Timer, calendar next event, file shelf.
```

with:

```
- Timer, file shelf. (Calendar moved up to Phase 3.)
```

- [ ] **Step 3: Update §6.3's "Later" table**

Remove the `| Calendar | EventKit | Calendars |` row — it is implemented as of Phase 3.

- [ ] **Step 4: Add a §5.2 power rule**

Add to the §5.2 rules list:

```
- Calendar refreshes **only** on `.EKEventStoreChanged` (and display wake). No polling,
  no periodic re-fetch.
```

- [ ] **Step 5: Add §0 TL;DR rows**

Add two rows to the §0 decisions table:

```
| Island material | `NSVisualEffectView(.hudWindow)` under a state-driven black overlay | Closed must stay pure black to masquerade as the hardware notch; the material only reads through once the shape grows past the real cutout. Reduce Transparency falls back to solid fill |
| Expanded size | 600×220 (was 320×120) | The two-column agenda is the point of the idle-expanded state and doesn't fit at 320pt. Accepts more menu-bar overlap while expanded, consistent with the existing overlap decision |
```

- [ ] **Step 6: Stop for review**

No build needed — documentation only. Confirm the Markdown tables still render (no broken pipes).

---

### Task 11: Manual verification checklist

Needs the user's eyes on real hardware — a notched Mac, a real media app, and a populated calendar.

**Files:** None — this task is a checklist, not code.

- [ ] Reduce Transparency ON (System Settings → Accessibility → Display): solid black fill, no material, no edge bleed, in closed / compact / expanded.
- [ ] Reduce Transparency OFF: material reads through in expanded; closed is still indistinguishable from the hardware notch.
- [ ] **Regression guard:** closed island still invisible against the physical notch (the Phase 1 acceptance criterion the material could most easily break).
- [ ] Reduce Motion ON: no springs anywhere — including chip bar entrance/exit and album-art swap.
- [ ] Mood chip bar appears only while playback is active; exits on pause as a reverse of its entrance (slide + fade), not a plain fade-out.
- [ ] Chips are clickable and the row scrolls horizontally; the row never widens the island above it.
- [ ] Click-through still works everywhere outside the shape and outside the chip row.
- [ ] Idle-expanded shows the two-column agenda, correct date header, and a correct "+N more events" count.
- [ ] Idle → music-live: the calendar column compresses and the music column grows in **one** coordinated animation, not two sequential ones.
- [ ] Track skip: album art crossfades with a scale-pop, title/artist crossfade, transport icons do **not** animate.
- [ ] Play ↔ pause: the icon crossfades and scales rather than hard-cutting.
- [ ] Swipe left on expanded music → next track; swipe right → previous.
- [ ] Calendar permission denied (revoke in System Settings → Privacy → Calendars): expanded shows music-only or "Nothing scheduled"; no nag, no blank crash, no hang.
- [ ] Calendar permission granted: today's events appear, and editing an event in Calendar.app updates the notch without a restart (proves `.EKEventStoreChanged` wiring).
- [ ] Idle CPU with nothing playing: still ~0.0% (Activity Monitor → Energy). Proves the calendar observer isn't waking anything.
- [ ] CPU while playing + expanded + chips visible, hovering repeatedly for 30s: under 0.5%, no stuck states, no dropped frames.

---

## Self-Review Notes

- **Spec coverage:** §5 geometry → Task 1. §6 material + accessibility → Tasks 3, 4. §7 calendar → Tasks 5, 6. §8 view hierarchy → Tasks 7, 8, 9. §9 motion → Tasks 2, 8. §10 hit-testing → Task 9 Step 4. §11 testing → Tasks 5 (unit) and 11 (manual). §12 RESEARCH.md updates → Task 10. §13 risks → the `NSCalendarsFullAccessUsageDescription` risk was retired by verifying the key against the real SDK before writing this plan; the rest are covered by Task 11's checklist.
- **Spec §8's open question** (SignatureGlow / ClockPlaceholderView / ExpandedBatteryRow) resolved per the spec's stated default: **keep all three**. Task 8 Step 1 moves `SignatureGlow` to its own file so both root and idle views can use it; Task 9 Step 1 retains clock and battery in `topRow`.
- **Type consistency:** `CalendarEvent`'s fields (`id`/`title`/`start`/`end`/`isAllDay`/`colorHex`) are defined in Task 5 and consumed identically in Tasks 6 (`CalendarService.convert`), 7 (`EventRow`), and 8 (both expanded views). `CalendarEventMapper.upcoming(_:now:limit:)` and `.overflowCount(total:shown:)` keep the same signatures in Tasks 5, 8. `NotchGeometry.chipBarHeight`/`chipBarGap` defined in Task 1, used in Tasks 8, 9. The five `Motion` tokens defined in Task 2 are each used at least once in Tasks 8–9.
- **Deliberate mid-plan dead code:** Tasks 2–8 each build clean while unreferenced; Task 9 is the single wiring point. This matches the Phase 2 plan's structure, where Tasks 4–7 were dead until Task 8.
- **Coordinate-space hazard flagged twice on purpose:** `NotchGeometry` is bottom-left origin (Task 1), `NotchContentView` is flipped/top-left (Task 9 Step 4). These are opposite conventions in the same plan and are the most likely source of an off-by-a-frame bug.
