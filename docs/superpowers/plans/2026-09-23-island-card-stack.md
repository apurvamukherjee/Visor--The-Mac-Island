# Island Card Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the expanded island's paging into a visible deck — two adjacent pages peek as tinted chins below the front card, and the stack cycles endlessly in both directions.

**Architecture:** A new `IslandStack` view draws one `NotchShape` per reachable page in a `ZStack`, each displaced by its *depth* (distance from the front along the swipe axis). Page changes animate depth, so the rise-and-fall motion falls out of one animated property rather than three coordinated transitions. The front card keeps today's geometry exactly; everything is additive and lives below it. A `PagingStyle` preference selects between today's cross-fade and the stack, with the unwritten key resolving to cross-fade.

**Tech Stack:** Swift 6 (language mode, strict concurrency: complete), SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-23-island-card-stack-design.md`

## Global Constraints

- Swift 6 language mode, strict concurrency complete. Everything touching `NotchStore` is `@MainActor`.
- SwiftUI for all views; AppKit only in `Window/` and `App/`.
- macOS 14.0 minimum, Apple silicon.
- No third-party Swift packages. Nothing in this plan needs one.
- No force unwraps, no `try!`, no `print()` — use `os.Logger` if logging is needed (it is not, here).
- Comments explain *why*, not *what*. No TODOs without an issue reference.
- All animations come from `Motion` tokens. No raw `.spring`/`.easeInOut`/durations anywhere else.
- Event-driven only. No polling loops. No timers except `Task.sleep` with cancellation.
- Never animate a **layout** property (`frame`, `padding`) in a loop — RESEARCH §5.1b. Depth animation uses `offset`, `padding` set once per page change (not per frame), and `scaleEffect`.
- §2.1 governing rule: nothing changes by default. Every new key must read as today's behaviour when unwritten.
- Run `xcodegen generate` after touching `project.yml`. New files under existing directories need no project.yml change — XcodeGen globs them.
- Before saying a task is done: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`, `xcodebuild -scheme Visor test | xcbeautify`, `swiftformat .`, `swiftlint`.
- Never commit unless the user asks. Each task's commit step is written out but **held** until the user says so.

## File Structure

| File | Responsibility |
|---|---|
| `Visor/Core/PagingStyle.swift` | **Create.** The style enum; `.crossFade` is the unwritten-key case. |
| `Visor/Support/Preferences.swift` | **Modify.** Two keys, their accessors, both added to `ownKeys`. |
| `Visor/Core/IslandPage.swift` | **Modify.** `cycled(by:in:)`, `tint`, `chinTintOpacity`. `stepped` untouched. |
| `Visor/Core/IslandLayout.swift` | **Modify.** `chinReveal` stored property, defaulted 0. |
| `Visor/Core/NotchStore+Layout.swift` | **Modify.** `chinReveal` resolution; `stackDepths`. |
| `Visor/Core/Dwell.swift` | **Modify.** `stackReveal`, `stackRetract`. |
| `Visor/UI/IslandStack.swift` | **Create.** The ZStack of cards. Pure view, no store writes. |
| `Visor/UI/NotchRootView.swift` | **Modify.** Route through `IslandStack` when the style is `.cardStack`. |
| `Visor/Window/NotchWindowController+Paging.swift` | **Modify.** `cycled` when stacked, `stepped` otherwise. |
| `Visor/Window/NotchWindowController.swift` | **Modify.** Retract-before-collapse; frame grows by `chinReveal`. |
| `Visor/Support/NewFeatures.swift` | **Modify.** `islandStackTint`, appended to `all`. |
| `Visor/App/NewFeaturesView.swift` | **Modify.** Style picker, tint toggle, reveal slider. |
| `VisorTests/PagingStyleTests.swift` | **Create.** Unwritten and unrecognised keys resolve `.crossFade`. |
| `VisorTests/IslandPageCycleTests.swift` | **Create.** Wrap both directions; `stepped` still clamps. |
| `VisorTests/IslandStackTests.swift` | **Create.** Depth table; `chinReveal` gating. |
| `VisorTests/PreferencesRestoreTests.swift` | **Modify.** Assert both new keys are resettable. |

Task order is dependency order: preference → page model → layout → view → gesture → window → settings. Tasks 1–3 are pure logic with no view work, so they carry the bulk of the tests.

---

### Task 1: Paging style preference

The style selector, and the two keys, before anything reads them. Ships with nothing wired up — selecting `.cardStack` changes nothing yet, which is what makes this task independently reviewable.

**Files:**
- Create: `Visor/Core/PagingStyle.swift`
- Create: `VisorTests/PagingStyleTests.swift`
- Modify: `Visor/Support/Preferences.swift`
- Modify: `VisorTests/PreferencesRestoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum PagingStyle: String, CaseIterable, Sendable { case crossFade, cardStack }`
  - `PagingStyle.title: String`
  - `PagingStyle.detail: String`
  - `static PagingStyle.current(in: UserDefaults = .standard) -> PagingStyle`
  - `Preferences.pagingStyleKey: String` = `"islandPagingStyle"`
  - `Preferences.stackRevealDelayKey: String` = `"islandStackRevealMilliseconds"`
  - `Preferences.stackRevealDelayDefault: Double` = `600`
  - `Preferences.stackRevealDelayRange: ClosedRange<Double>` = `0 ... 1500`
  - `static Preferences.stackRevealDelayMilliseconds(in: UserDefaults) -> Double`
  - `static Preferences.stackRevealDelay: Duration`

- [ ] **Step 1: Write the failing test**

Create `VisorTests/PagingStyleTests.swift`:

```swift
import Foundation
import Testing
@testable import Visor

/// §2.1 in the one place it is easiest to break: a stored *value* has no
/// `bool(forKey:)` false to ride, so the guarantee has to come from the
/// resolution instead. An unwritten key, and anything unrecognised, is
/// today's behaviour.
@Suite("Paging style")
struct PagingStyleTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    @Test("An unwritten key is today's behaviour")
    func unwrittenKeyIsCrossFade() {
        #expect(PagingStyle.current(in: makeDefaults()) == .crossFade)
    }

    @Test("A key written by a future version does not break this one")
    func unrecognisedValueIsCrossFade() {
        let defaults = makeDefaults()
        defaults.set("carousel", forKey: Preferences.pagingStyleKey)

        #expect(PagingStyle.current(in: defaults) == .crossFade)
    }

    @Test("The stack is selected only by writing it")
    func storedValueResolves() {
        let defaults = makeDefaults()
        defaults.set(PagingStyle.cardStack.rawValue, forKey: Preferences.pagingStyleKey)

        #expect(PagingStyle.current(in: defaults) == .cardStack)
    }

    @Test("Reveal delay defaults to 600ms and clamps to its range")
    func revealDelayDefaultsAndClamps() {
        let defaults = makeDefaults()
        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 600)

        defaults.set(9000.0, forKey: Preferences.stackRevealDelayKey)
        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 1500)

        defaults.set(-40.0, forKey: Preferences.stackRevealDelayKey)
        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 0)
    }

    /// 0 is a real choice — chins out from the moment the island opens —
    /// not a missing value. Same distinction `hoverIntentDelay` draws.
    @Test("Zero is a stored choice, not an absent one")
    func zeroIsAChoice() {
        let defaults = makeDefaults()
        defaults.set(0.0, forKey: Preferences.stackRevealDelayKey)

        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 0)
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `xcodebuild -scheme Visor test -only-testing:VisorTests/PagingStyleTests | xcbeautify`
Expected: FAIL — compile error, `cannot find 'PagingStyle' in scope`.

- [ ] **Step 3: Create the enum**

Create `Visor/Core/PagingStyle.swift`:

```swift
import Foundation

/// How the expanded island moves between its screens.
///
/// A picker rather than a `NewFeature` switch, because the two candidate
/// booleans (`stack`, `stackTint`) give four states and one of them — tint
/// on, stack off — means nothing. The §2.1 guarantee survives the change of
/// shape: `.crossFade` is what an unwritten *or unrecognised* key resolves
/// to, so an unset default is today's behaviour exactly as `bool(forKey:)`'s
/// false is for the switches. Same construction as `NotchScreenChoice`.
enum PagingStyle: String, CaseIterable, Sendable {
    /// What Visor does today: one box, content swapped in place.
    case crossFade
    /// The deck — adjacent pages peek below the front card and the stack
    /// cycles.
    case cardStack

    var title: String {
        switch self {
        case .crossFade: "Cross-fade"
        case .cardStack: "Card stack"
        }
    }

    var detail: String {
        switch self {
        case .crossFade: "Pages swap in place inside one box."
        case .cardStack: "Adjacent pages peek below the front card, and the stack cycles."
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> PagingStyle {
        PagingStyle(rawValue: defaults.string(forKey: Preferences.pagingStyleKey) ?? "") ?? .crossFade
    }
}
```

- [ ] **Step 4: Add the keys and accessors**

In `Visor/Support/Preferences.swift`, after the `hoverIntentDelay` block (around line 111), add:

```swift
    // MARK: - Paging

    /// `PagingStyle.rawValue`. Unset is `.crossFade` — see `PagingStyle`.
    static let pagingStyleKey = "islandPagingStyle"

    /// How long after the island settles the chins slide out, in
    /// milliseconds. Like the hover delay this has a real default rather
    /// than an off position, so it cannot ride `bool(forKey:)`'s false; and
    /// like it, 0 is a choice (chins out from the start), not an absence.
    static let stackRevealDelayKey = "islandStackRevealMilliseconds"
    static let stackRevealDelayDefault = 600.0
    static let stackRevealDelayRange: ClosedRange<Double> = 0 ... 1500

    static var stackRevealDelay: Duration {
        .milliseconds(Int(stackRevealDelayMilliseconds(in: .standard)))
    }

    static func stackRevealDelayMilliseconds(in defaults: UserDefaults) -> Double {
        guard let stored = defaults.object(forKey: stackRevealDelayKey) as? Double else {
            return stackRevealDelayDefault
        }
        return min(max(stored, stackRevealDelayRange.lowerBound), stackRevealDelayRange.upperBound)
    }
```

- [ ] **Step 5: Add both keys to `ownKeys`**

In the same file, in the `ownKeys` array (around line 138), add after `hoverIntentDelayKey`:

```swift
        pagingStyleKey,
        stackRevealDelayKey,
```

This is the `launchGroupsKey` bug from the 2026-09-23 audit: a key declared beside its neighbours but never listed here survives "Restore original settings", and `PreferencesRestoreTests` iterates the list, so the omission is invisible to the test. Keys and list entries land together.

- [ ] **Step 6: Pin the restore in its own test**

In `VisorTests/PreferencesRestoreTests.swift`, add:

```swift
    /// Named explicitly, not just covered by the iteration: the iteration
    /// reads `resettableKeys`, so a key missing from that list is invisible
    /// to it. This is the assertion that would have caught `launchGroups`.
    @Test("Paging keys are restorable")
    func pagingKeysAreRestorable() {
        #expect(Preferences.resettableKeys.contains(Preferences.pagingStyleKey))
        #expect(Preferences.resettableKeys.contains(Preferences.stackRevealDelayKey))
    }
```

- [ ] **Step 7: Run the tests**

Run: `xcodebuild -scheme Visor test -only-testing:VisorTests/PagingStyleTests -only-testing:VisorTests/PreferencesRestoreTests | xcbeautify`
Expected: PASS.

- [ ] **Step 8: Format, lint, full build**

```bash
swiftformat . && swiftlint && xcodebuild -scheme Visor -configuration Debug build | xcbeautify
```
Expected: 0 warnings from the build; swiftlint no worse than the known 3.

- [ ] **Step 9: Commit** (hold until the user asks)

```bash
git add Visor/Core/PagingStyle.swift Visor/Support/Preferences.swift \
        VisorTests/PagingStyleTests.swift VisorTests/PreferencesRestoreTests.swift
git commit -m "feat: paging style preference, defaulting to today's cross-fade"
```

---

### Task 2: Cycling and per-page tint

The page model. `stepped` is left exactly as it is — the off path must stay byte-identical — and cycling arrives beside it.

**Files:**
- Modify: `Visor/Core/IslandPage.swift`
- Create: `VisorTests/IslandPageCycleTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `IslandPage.cycled(by: Int, in: [IslandPage]) -> IslandPage`
  - `IslandPage.tint: Color`
  - `IslandPage.usesMaterialChin: Bool`

- [ ] **Step 1: Write the failing test**

Create `VisorTests/IslandPageCycleTests.swift`:

```swift
import Foundation
import Testing
@testable import Visor

/// The stack has no ends. `stepped` still does — both live, and which one a
/// swipe reaches is the paging style's business, not this type's.
@Suite("Island page cycling")
struct IslandPageCycleTests {
    private let all: [IslandPage] = [.agenda, .home, .usage]

    @Test("Down from the last page wraps to the first")
    func wrapsForward() {
        #expect(IslandPage.usage.cycled(by: 1, in: all) == .agenda)
        #expect(IslandPage.agenda.cycled(by: 1, in: all) == .home)
        #expect(IslandPage.home.cycled(by: 1, in: all) == .usage)
    }

    @Test("Up from the first page wraps to the last")
    func wrapsBackward() {
        #expect(IslandPage.agenda.cycled(by: -1, in: all) == .usage)
        #expect(IslandPage.usage.cycled(by: -1, in: all) == .home)
        #expect(IslandPage.home.cycled(by: -1, in: all) == .agenda)
    }

    /// The idle island drops `.agenda` — `.home` already draws it. Two pages
    /// cycle by alternating, and both directions agree, which is the one
    /// case where wrapping and clamping visibly differ by nothing.
    @Test("Two reachable pages alternate in both directions")
    func twoPagesAlternate() {
        let two: [IslandPage] = [.home, .usage]

        #expect(IslandPage.home.cycled(by: 1, in: two) == .usage)
        #expect(IslandPage.usage.cycled(by: 1, in: two) == .home)
        #expect(IslandPage.home.cycled(by: -1, in: two) == .usage)
        #expect(IslandPage.usage.cycled(by: -1, in: two) == .home)
    }

    @Test("A page no longer in the stack cycles home")
    func absentPageGoesHome() {
        #expect(IslandPage.agenda.cycled(by: 1, in: [.home, .usage]) == .home)
    }

    @Test("An empty stack cannot move")
    func emptyStackHolds() {
        #expect(IslandPage.home.cycled(by: 1, in: []) == .home)
    }

    /// The off path. With the stack unselected a swipe still clamps, so
    /// these are the assertions that fail if cycling leaks into `stepped`.
    @Test("Stepping still clamps at both ends")
    func steppingStillClamps() {
        #expect(IslandPage.usage.stepped(by: 1, in: all) == .usage)
        #expect(IslandPage.agenda.stepped(by: -1, in: all) == .agenda)
    }

    @Test("Every page has its own tint")
    func tintsAreDistinct() {
        let tints = IslandPage.allCases.map(\.tint)
        #expect(Set(tints.map(\.description)).count == tints.count)
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `xcodebuild -scheme Visor test -only-testing:VisorTests/IslandPageCycleTests | xcbeautify`
Expected: FAIL — `value of type 'IslandPage' has no member 'cycled'`.

- [ ] **Step 3: Add cycling and tint**

In `Visor/Core/IslandPage.swift`, change the import line to `import SwiftUI` (it currently has none — the file is pure `Foundation` today, and `Color` needs SwiftUI). Then add inside the enum, after `stepped(by:in:)`:

```swift
    /// One step with no ends — past the last page is the first again.
    ///
    /// The deliberate sibling of `stepped`, not a replacement for it. A
    /// stack you can see the edges of wants to clamp; a stack drawn as a
    /// deck, where the page behind the last one is visibly the first, wants
    /// to wrap, and a gesture that dies at an end you can *see* continuing
    /// reads as broken. Which one a swipe reaches is `PagingStyle`'s call.
    ///
    /// Negative-safe: Swift's `%` keeps the sign of the dividend, so a
    /// backward wrap needs the extra `+ count` before the second modulo.
    func cycled(by delta: Int, in available: [IslandPage]) -> IslandPage {
        let stack = available.sorted { $0.rawValue < $1.rawValue }
        guard !stack.isEmpty else { return self }
        guard let index = stack.firstIndex(of: self) else { return .home }
        let count = stack.count
        return stack[((index + delta) % count + count) % count]
    }

    /// What the page's chin is tinted, so two lips 9pt tall read as
    /// different screens rather than as one drop shadow.
    ///
    /// Only the chins carry this by default. The front card stays pure
    /// black unless `NewFeatures.islandStackTint` is on — `NotchRootView`
    /// records two earlier attempts at a non-black surface that both washed
    /// out against a bright wallpaper, and a tinted front card becomes the
    /// colour the island *closes* in.
    var tint: Color {
        switch self {
        case .agenda: .white
        case .home: .clear
        case .usage: .orange
        }
    }

    /// The agenda's lip is a glass edge rather than a wash of colour — it is
    /// the page with no accent of its own, and a white tint at chin opacity
    /// is indistinguishable from the island lightening.
    var usesMaterialChin: Bool {
        self == .agenda
    }
```

- [ ] **Step 4: Run the tests**

Run: `xcodebuild -scheme Visor test -only-testing:VisorTests/IslandPageCycleTests -only-testing:VisorTests/IslandPageTests | xcbeautify`
Expected: PASS, including the existing `IslandPageTests`.

- [ ] **Step 5: Format, lint, build**

```bash
swiftformat . && swiftlint && xcodebuild -scheme Visor -configuration Debug build | xcbeautify
```

- [ ] **Step 6: Commit** (hold until the user asks)

```bash
git add Visor/Core/IslandPage.swift VisorTests/IslandPageCycleTests.swift
git commit -m "feat: endless page cycling and per-page tint"
```

---

### Task 3: Chin reveal in the layout

How much taller the island is when the stack is on, and which depth each page sits at. Pure arithmetic — still no view.

**Files:**
- Modify: `Visor/Core/IslandLayout.swift`
- Modify: `Visor/Core/NotchStore+Layout.swift`
- Modify: `Visor/Core/Dwell.swift`
- Create: `VisorTests/IslandStackTests.swift`

**Interfaces:**
- Consumes: `PagingStyle.current(in:)` (Task 1), `IslandPage.cycled` (Task 2).
- Produces:
  - `IslandLayout.chinReveal: CGFloat` (stored, defaults 0)
  - `IslandStackMetrics.chinOffset: CGFloat` = 9
  - `IslandStackMetrics.chinInset: CGFloat` = 11
  - `IslandStackMetrics.chinRadiusDrop: CGFloat` = 3
  - `IslandStackMetrics.maxDepth: Int` = 2
  - `IslandStackMetrics.reveal(forDepths:) -> CGFloat`
  - `NotchStore.pagingStyle: PagingStyle` (stored, defaults `PagingStyle.current()`)
  - `NotchStore.isCardStacked: Bool`
  - `NotchStore.stackDepths: [IslandPage: Int]`
  - `Dwell.stackReveal: Duration`, `Dwell.stackRetract: Duration`

- [ ] **Step 1: Write the failing test**

Create `VisorTests/IslandStackTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Visor

/// The deck's arithmetic. Depth is distance from the front along the swipe
/// axis, and it is what every card's offset, inset and radius derive from —
/// so these assertions are the geometry, not a proxy for it.
@MainActor
@Suite("Island stack")
struct IslandStackTests {
    private func makeStore(style: PagingStyle) -> NotchStore {
        let store = NotchStore()
        store.pagingStyle = style
        return store
    }

    @Test("The front page is depth 0 and the rest recede")
    func depthsCountFromTheFront() {
        let depths = IslandStackMetrics.depths(front: .home, in: [.agenda, .home, .usage])

        #expect(depths[.home] == 0)
        #expect(depths[.usage] == 1)
        #expect(depths[.agenda] == 2)
    }

    /// Depth follows the cycle, so the page "before" the front is at the
    /// back rather than at a negative depth. A card at -1 would draw above
    /// the front one and hide it.
    @Test("Depth wraps with the stack, never going negative")
    func depthsWrap() {
        let depths = IslandStackMetrics.depths(front: .usage, in: [.agenda, .home, .usage])

        #expect(depths[.usage] == 0)
        #expect(depths[.agenda] == 1)
        #expect(depths[.home] == 2)
    }

    @Test("Two pages make one chin")
    func twoPagesOneChin() {
        let depths = IslandStackMetrics.depths(front: .home, in: [.home, .usage])

        #expect(depths[.home] == 0)
        #expect(depths[.usage] == 1)
        #expect(IslandStackMetrics.reveal(forDepths: depths.values.max() ?? 0) == 9)
    }

    @Test("Reveal is the deepest chin's offset")
    func revealFollowsDeepestChin() {
        #expect(IslandStackMetrics.reveal(forDepths: 0) == 0)
        #expect(IslandStackMetrics.reveal(forDepths: 1) == 9)
        #expect(IslandStackMetrics.reveal(forDepths: 2) == 18)
    }

    @Test("A stack of one is just the island")
    func singlePageHasNoReveal() {
        let depths = IslandStackMetrics.depths(front: .home, in: [.home])

        #expect(depths[.home] == 0)
        #expect(IslandStackMetrics.reveal(forDepths: depths.values.max() ?? 0) == 0)
    }

    @Test("Cross-fade adds no height at all")
    func crossFadeAddsNothing() {
        let store = makeStore(style: .crossFade)
        store.activate(.nowPlaying)

        #expect(store.isCardStacked == false)
        #expect(store.layout.chinReveal == 0)
    }

    /// The load-bearing one for §2.1: with the style unselected the resolved
    /// box must be the number today's build produces, not merely a small one.
    @Test("Selecting the stack changes the box by exactly the reveal")
    func stackGrowsBoxByReveal() {
        let flat = makeStore(style: .crossFade)
        flat.activate(.nowPlaying)
        let stacked = makeStore(style: .cardStack)
        stacked.activate(.nowPlaying)

        let grew = stacked.layout.expandedExtraHeight - flat.layout.expandedExtraHeight
        #expect(grew == stacked.layout.chinReveal)
        #expect(stacked.layout.chinReveal > 0)
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `xcodebuild -scheme Visor test -only-testing:VisorTests/IslandStackTests | xcbeautify`
Expected: FAIL — `cannot find 'IslandStackMetrics' in scope`.

**Note on `NotchStore(defaults:)`:** it does not exist, and `NotchStore` never touches `UserDefaults` at all — every preference reaches it through `@AppStorage` in views or a static read. Adding a defaults dependency to the store to satisfy a test would be the tail wagging the dog.

Instead, give the store a stored style with a resolved default:

```swift
    /// Which way paging is drawn. Stored rather than read live because the
    /// layout is recomputed on every observation tick and `PagingStyle`
    /// resolution is a `UserDefaults` string read — the same reason the
    /// accessibility flags are cached in `Motion`.
    var pagingStyle = PagingStyle.current()
```

Set it from `@AppStorage` in the settings pane's `onChange`, or re-read it on expand. The tests then assign `store.pagingStyle = .cardStack` directly and need no defaults suite at all — replace `makeDefaults(style:)` in `IslandStackTests` with direct assignment, and drop the `NotchStore(defaults:)` calls for plain `NotchStore()`. `isCardStacked` reads `pagingStyle`, not `PagingStyle.current()`.

- [ ] **Step 3: Add the metrics**

In `Visor/Core/IslandLayout.swift`, add after the `NotchRadii` struct:

```swift
/// The deck's constants, in one place because they move together: raise the
/// offset without the inset and the chins stop reading as *behind* the front
/// card and start reading as a lip on it.
enum IslandStackMetrics {
    /// How far each chin sits below the card in front of it.
    static let chinOffset: CGFloat = 9
    /// How far each chin is drawn in at the sides. This is what makes a
    /// chin read as a card behind rather than a second edge on the same
    /// shape — an equal-width card peeking under another is one silhouette
    /// with a lip, not two cards.
    static let chinInset: CGFloat = 11
    /// How much rounder each chin is than the card in front, so the stack
    /// recedes instead of reading as three identical slabs.
    static let chinRadiusDrop: CGFloat = 3
    /// Three pages exist, so two chins. A fourth page extends the table
    /// rather than redesigning it.
    static let maxDepth = 2

    /// Distance from the front along the swipe axis, per page.
    ///
    /// Taken from the cycle, so the page "before" the front sits at the
    /// *back* rather than at a negative depth — a card at -1 would draw over
    /// the front one and hide it.
    static func depths(front: IslandPage, in available: [IslandPage]) -> [IslandPage: Int] {
        let stack = available.sorted { $0.rawValue < $1.rawValue }
        guard let start = stack.firstIndex(of: front) else { return [front: 0] }
        return stack.enumerated().reduce(into: [:]) { depths, entry in
            depths[entry.element] = (entry.offset - start + stack.count) % stack.count
        }
    }

    /// How far the deepest chin protrudes below the front card.
    static func reveal(forDepths deepest: Int) -> CGFloat {
        CGFloat(min(deepest, maxDepth)) * chinOffset
    }
}
```

- [ ] **Step 4: Add `chinReveal` to the layout**

In `IslandLayout`'s stored properties, after `compactExtraWidth`:

```swift
    /// How far the chins protrude below the front card. Zero unless the card
    /// stack is on *and* more than one page is reachable — a stack of one is
    /// just the island. Added to the expanded height rather than taken out
    /// of it: the front card keeps the size it has today, and the deck grows
    /// downward from it.
    var chinReveal: CGFloat = 0
```

In `expandedSize(closed:)`, add the reveal to the height:

```swift
    func expandedSize(closed: CGSize) -> CGSize {
        CGSize(
            width: closed.width + expandedExtraWidth,
            height: closed.height + expandedExtraHeight + chinReveal
        )
    }
```

In `covering(_:)`, carry the receiver's reveal — it is the box's property, not a page's:

```swift
    func covering(_ other: IslandLayout) -> IslandLayout {
        var box = self
        box.expandedExtraWidth = max(expandedExtraWidth, other.expandedExtraWidth)
        box.expandedExtraHeight = max(expandedExtraHeight, other.expandedExtraHeight)
        return box
    }
```

(unchanged — `chinReveal` rides on `self` already; this step is a no-op confirmation, do not edit it.)

- [ ] **Step 5: Resolve it in the store**

In `Visor/Core/NotchStore+Layout.swift`, in `var layout`, replace the final `return` with:

```swift
        let box = availablePages.reduce(activity) { $0.covering(pageLayout(for: $1)) }
        guard isCardStacked else { return box }
        var stacked = box
        stacked.chinReveal = IslandStackMetrics.reveal(
            forDepths: stackDepths.values.max() ?? 0
        )
        return stacked
```

Then add:

```swift
    /// Whether the island is drawing its screens as a deck. Paging has to be
    /// on for it to mean anything — the stack is how pages are *shown*, not
    /// a second way to reach them.
    var isCardStacked: Bool {
        NewFeatures.islandPaging.isEnabled() && pagingStyle == .cardStack
    }

    /// Each reachable page's distance from the front.
    ///
    /// Note `pagingStyle` itself is declared in `NotchStore.swift` beside
    /// `islandPage`, not here — this file holds derived geometry only.
    var stackDepths: [IslandPage: Int] {
        IslandStackMetrics.depths(front: islandPage, in: availablePages)
    }
```

- [ ] **Step 6: Add the two dwell constants**

In `Visor/Core/Dwell.swift`, add:

```swift
    /// How long after the island settles the chins slide out. The default
    /// behind `Preferences.stackRevealDelay`, which a slider overrides —
    /// this is the number that ships, not the one that is read.
    static let stackReveal: Duration = .milliseconds(600)
    /// How long the chins take to retract before the island collapses.
    /// Load-bearing, not styling: the frame must never be smaller than what
    /// is drawn. See `NotchWindowController.collapse`.
    static let stackRetract: Duration = .milliseconds(120)
```

- [ ] **Step 7: Run the tests**

Run: `xcodebuild -scheme Visor test -only-testing:VisorTests/IslandStackTests -only-testing:VisorTests/IslandLayoutTests | xcbeautify`
Expected: PASS, including the existing `IslandLayoutTests` — if one of those now fails, the reveal has leaked into the cross-fade path, which is the §2.1 violation this task exists to avoid.

- [ ] **Step 8: Format, lint, build**

```bash
swiftformat . && swiftlint && xcodebuild -scheme Visor -configuration Debug build | xcbeautify
```

- [ ] **Step 9: Commit** (hold until the user asks)

```bash
git add Visor/Core/IslandLayout.swift Visor/Core/NotchStore+Layout.swift \
        Visor/Core/Dwell.swift VisorTests/IslandStackTests.swift
git commit -m "feat: chin reveal and stack depth resolution"
```

---

### Task 4: The stack view

Where the deck is drawn. One `NotchShape` per page, displaced by depth.

**Files:**
- Create: `Visor/UI/IslandStack.swift`
- Modify: `Visor/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `IslandStackMetrics` (Task 3), `IslandPage.tint`/`.usesMaterialChin` (Task 2), `NotchStore.stackDepths`/`.isCardStacked` (Task 3).
- Produces: `IslandStack` — a `View` taking `store`, `size`, `radii`, `isRevealed`, and a `@ViewBuilder` front-card closure.

- [ ] **Step 1: Write the view**

There is no unit test for this step — it is a pure view, and the arithmetic it draws from is already pinned by `IslandStackTests`. Verification is the build plus the hardware checklist in Task 7.

Create `Visor/UI/IslandStack.swift`:

```swift
import SwiftUI

/// The expanded island drawn as a deck: the front card exactly as it is
/// today, and one chin per other reachable page peeking below it.
///
/// **Why three `NotchShape`s and not one path.** CLAUDE.md's rule is that
/// one black shape morphs between states and two shapes are never
/// cross-faded. These never cross-fade — they translate between depths, and
/// every one of them is the same silhouette at a different offset, so there
/// is still one shape vocabulary. Growing `NotchShape.path(in:)` into
/// stacked lips was the alternative and was rejected: that file is already
/// flagged by swiftlint for size and complexity, the shape must still morph
/// to `.closed`, and a single path cannot animate its lips independently of
/// its body.
///
/// **Why depth and not a transition.** Each card reads its own depth from
/// the store and animates to it; the page change happens inside one
/// `withAnimation`, so the whole deck springs together. The outgoing front
/// card travels to the back and the chin below it rises into the front
/// position without any of that being choreographed — it is one animated
/// property, not three coordinated transitions.
struct IslandStack<Front: View>: View {
    var store: NotchStore
    var size: CGSize
    var radii: NotchRadii
    /// False until the reveal delay has passed, and again while the island
    /// is retracting before a collapse. The chins sit at depth 0 — exactly
    /// behind the front card — when it is false.
    var isRevealed: Bool
    @ViewBuilder var front: () -> Front

    private var chins: [(page: IslandPage, depth: Int)] {
        store.stackDepths
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { (page: $0.key, depth: $0.value) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(chins, id: \.page) { chin in
                chinCard(page: chin.page, depth: chin.depth)
            }
            front()
        }
    }

    /// One peeking card. Drawn at the front card's full size and pushed
    /// down, rather than drawn as a short lip: a lip would have to know the
    /// front card's radius to meet it cleanly, and this way the geometry is
    /// the same shape every time.
    private func chinCard(page: IslandPage, depth: Int) -> some View {
        let step = CGFloat(min(depth, IslandStackMetrics.maxDepth))
        var chinRadii = radii
        chinRadii.bottom = max(0, radii.bottom - step * IslandStackMetrics.chinRadiusDrop)
        // No shoulder on a chin: the flare exists to blend the island into
        // the menu bar, and a card 9pt further down has no bezel to meet.
        chinRadii.top = 0
        let shape = NotchShape(chinRadii, isCapsule: store.isCapsule)

        return shape
            .fill(.black)
            .overlay {
                if page.usesMaterialChin {
                    shape.fill(.ultraThinMaterial).opacity(0.5)
                } else {
                    shape.fill(page.tint.opacity(0.22))
                }
            }
            .frame(
                width: max(0, size.width - step * 2 * IslandStackMetrics.chinInset),
                height: size.height
            )
            .offset(y: isRevealed ? step * IslandStackMetrics.chinOffset : 0)
    }
}
```

- [ ] **Step 2: Route the root view through it**

In `Visor/UI/NotchRootView.swift`, add the reveal state near the other `@AppStorage` properties:

```swift
    @State private var isStackRevealed = false
    @State private var revealTask: Task<Void, Never>?
```

Extract today's body chain into `islandCard` — take the existing `islandSurface.frame(...).overlay(...).overlay(...)` chain up to and including `.clipShape(shape)` and name it:

```swift
    /// Today's island, unchanged: the black surface, its content, and the
    /// clip that keeps anything from painting outside the silhouette.
    private var islandCard: some View {
        islandSurface
            .frame(width: currentSize.width, height: currentSize.height)
            // ... existing .overlay(alignment: .top) blocks, unchanged ...
            .clipShape(shape)
    }
```

Then in `body`, replace the leading `islandSurface…clipShape(shape)` with:

```swift
        stackedCard
```

and add:

```swift
    /// The card, wrapped in its deck when the stack is on. With it off this
    /// is the card and nothing else — no extra view in the hierarchy, so the
    /// cross-fade path is what it has always been.
    @ViewBuilder
    private var stackedCard: some View {
        if store.isCardStacked, store.state == .expanded {
            IslandStack(
                store: store,
                size: currentSize,
                radii: radii,
                isRevealed: isStackRevealed
            ) {
                islandCard
            }
            .animation(Motion.resolved(Motion.morph), value: isStackRevealed)
            .animation(Motion.resolved(Motion.morph), value: store.islandPage)
            .task(id: store.state) { await revealChins() }
        } else {
            islandCard
        }
    }

    /// The chins slide out a beat after the island settles, so opening shows
    /// one clean card and the deck then offers itself. Cancelled by the
    /// `.task(id:)` the moment the state changes, so a close mid-wait leaves
    /// nothing running — the same shape as `hoverIntentTask`.
    private func revealChins() async {
        guard store.state == .expanded else {
            isStackRevealed = false
            return
        }
        try? await Task.sleep(for: Preferences.stackRevealDelay)
        guard !Task.isCancelled else { return }
        isStackRevealed = true
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
Expected: 0 warnings. A `Sendable` complaint on the `@ViewBuilder` closure means `Front` needs no fix — the closure is `@MainActor` by virtue of `View`; re-check that `IslandStack` has no explicit `Sendable` conformance.

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild -scheme Visor test | xcbeautify`
Expected: all existing tests pass. Nothing here changes behaviour with the style unselected.

- [ ] **Step 5: Format, lint**

```bash
swiftformat . && swiftlint
```
Expected: swiftlint no worse than the known 3 warnings. If `NotchRootView.swift` now trips a size warning, that is the file growing past its limit — split `stackedCard` and `revealChins` into `NotchRootView+Stack.swift` rather than leaving a new violation standing, the way `SystemCommands+Files.swift` was split.

- [ ] **Step 6: Commit** (hold until the user asks)

```bash
git add Visor/UI/IslandStack.swift Visor/UI/NotchRootView.swift
git commit -m "feat: draw the expanded island as a deck of cards"
```

---

### Task 5: Cycling gesture and retract-before-collapse

The swipe reaches the cycle when the stack is on, and the chins retract before the frame shrinks.

**Files:**
- Modify: `Visor/Window/NotchWindowController+Paging.swift`
- Modify: `Visor/Window/NotchWindowController.swift`

**Interfaces:**
- Consumes: `IslandPage.cycled` (Task 2), `NotchStore.isCardStacked` (Task 3), `Dwell.stackRetract` (Task 3).
- Produces: `NotchWindowController.turned(by: Int) -> IslandPage`.

- [ ] **Step 1: Route the swipe through the cycle**

In `Visor/Window/NotchWindowController+Paging.swift`, add:

```swift
    /// Where a swipe of `delta` lands. The stack wraps; the cross-fade
    /// clamps. One place, so up and down cannot disagree about which.
    func turned(by delta: Int) -> IslandPage {
        store.isCardStacked
            ? store.islandPage.cycled(by: delta, in: store.availablePages)
            : store.islandPage.stepped(by: delta, in: store.availablePages)
    }
```

Then in `handleSwipeDismiss`, replace:

```swift
        turn(to: store.islandPage.stepped(by: -1, in: store.availablePages))
```

with:

```swift
        turn(to: turned(by: -1))
```

and in `handleSwipeRestore`, replace:

```swift
        turn(to: store.islandPage.stepped(by: 1, in: store.availablePages))
```

with:

```swift
        turn(to: turned(by: 1))
```

`turn(to:)` itself is unchanged — its `guard page != store.islandPage` already makes a no-op cycle (two pages, or one) silent, which is the behaviour its comment asks for.

- [ ] **Step 2: Retract before collapsing**

Find `collapse()` in `Visor/Window/NotchWindowController.swift`. Wrap its body so the chins retract first:

```swift
    func collapse() {
        guard store.isCardStacked, store.state == .expanded else {
            performCollapse()
            return
        }
        // The chins retract *before* the frame shrinks, and the order is
        // load-bearing rather than stylistic. The 2026-09-19 motion pass
        // found `setFrame` firing while geometry was still protruding and
        // clipping the still-moving corners — `.logicallyComplete` landing
        // 117ms before the spring did. Chins are that failure at a larger
        // scale: 18pt of card below the frame, cut off in a hard line.
        // The frame must never be smaller than what is drawn.
        store.isStackRetracting = true
        retractTask?.cancel()
        retractTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Dwell.stackRetract)
            guard !Task.isCancelled, let self else { return }
            store.isStackRetracting = false
            performCollapse()
        }
    }
```

Rename the existing body to `performCollapse()`, and add the task property beside `hoverIntentTask`:

```swift
    private var retractTask: Task<Void, Never>?
```

Cancel it wherever `hoverIntentTask` is cancelled — an expand arriving mid-retract must not be followed by the collapse it was racing:

```swift
        retractTask?.cancel()
        retractTask = nil
```

- [ ] **Step 3: Add the flag the view reads**

In `Visor/Core/NotchStore.swift`, beside `islandPage`:

```swift
    /// True while the chins are retracting ahead of a collapse. The view
    /// reads it to pull them back behind the front card; nothing else does.
    var isStackRetracting = false
```

In `NotchRootView`, change the reveal binding so retraction wins:

```swift
                isRevealed: isStackRevealed && !store.isStackRetracting,
```

- [ ] **Step 4: Build and run the full suite**

```bash
xcodebuild -scheme Visor -configuration Debug build | xcbeautify
xcodebuild -scheme Visor test | xcbeautify
```
Expected: 0 warnings, all tests pass. `SwipeAxisTests` and `IslandPageTests` both exercise this path — if either fails, the cycle has leaked into the cross-fade path.

- [ ] **Step 5: Format, lint**

```bash
swiftformat . && swiftlint
```

- [ ] **Step 6: Commit** (hold until the user asks)

```bash
git add Visor/Window/NotchWindowController+Paging.swift \
        Visor/Window/NotchWindowController.swift Visor/Core/NotchStore.swift \
        Visor/UI/NotchRootView.swift
git commit -m "feat: cycle the deck by swipe, retract chins before collapsing"
```

---

### Task 6: Settings

The picker, the tint switch and the reveal slider. Last, so every control it exposes already works.

**Files:**
- Modify: `Visor/Support/NewFeatures.swift`
- Modify: `Visor/App/NewFeaturesView.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `NewFeatures.islandStackTint`.

- [ ] **Step 1: Add the tint switch**

In `Visor/Support/NewFeatures.swift`, after `islandPaging`:

```swift
    /// The front card's own colour, separate from the chins' because the
    /// chins are the part that has to be distinguishable and the front card
    /// is the part with a rule about it. `NotchRootView` records two earlier
    /// attempts at a non-black surface that both washed out against a bright
    /// wallpaper; a tinted front card is also the colour the island *closes*
    /// in. Off, so the full-colour version can be seen on hardware without
    /// being committed to.
    static let islandStackTint = NewFeature(
        key: "newFeature.islandStackTint",
        title: "Tint the front card",
        detail: "With the card stack on, the whole island takes the colour of the screen "
            + "you are on rather than only the chins below it.",
        isRecommended: false
    )
```

Append `islandStackTint` to `all`.

- [ ] **Step 2: Add the controls**

In `Visor/App/NewFeaturesView.swift`, add to the properties:

```swift
    @AppStorage(Preferences.pagingStyleKey) private var pagingStyle = PagingStyle.crossFade.rawValue
    @AppStorage(Preferences.stackRevealDelayKey)
    private var stackReveal = Preferences.stackRevealDelayDefault
```

Add a section after the Hover section:

```swift
            Section {
                Picker("Paging style", selection: $pagingStyle) {
                    ForEach(PagingStyle.allCases, id: \.rawValue) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                LabeledSlider(
                    "Chin reveal delay",
                    value: $stackReveal,
                    range: Preferences.stackRevealDelayRange,
                    format: { "\(Int($0)) ms" }
                )
                .disabled(pagingStyle != PagingStyle.cardStack.rawValue)
            } header: {
                Text("Paging")
            } footer: {
                Text("How the island moves between its screens, and how long after it "
                    + "opens the chins slide out. 0 ms shows them straight away. "
                    + "Needs “Swipe between screens” on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
```

The tint switch needs disabling too. In `NewFeatureRow`'s call site, pass the style down, or — smaller — add to the `ForEach` in the first section:

```swift
                ForEach(NewFeatures.all) { feature in
                    NewFeatureRow(feature: feature)
                        .disabled(
                            feature.key == NewFeatures.islandStackTint.key
                                && pagingStyle != PagingStyle.cardStack.rawValue
                        )
                }
```

Disabled rather than hidden: a row that appears and vanishes under the cursor is worse than one that greys out.

- [ ] **Step 2b: Keep the store's copy in sync**

`NotchStore.pagingStyle` is stored (Task 3), so changing the picker must write through to it or the island keeps drawing the old style until relaunch. In whichever type owns the store and already observes settings — the same place `NotchScreenChoice` changes are picked up — re-read on change:

```swift
        store.pagingStyle = PagingStyle.current()
```

If nothing observes that key yet, the smallest correct hook is `NotchWindowController.expand()`: the style can only change while Settings is open, which means the island is closed, so re-reading it on the way open is never stale. Prefer that over a new observer.

- [ ] **Step 3: Build, test, format, lint**

```bash
xcodebuild -scheme Visor -configuration Debug build | xcbeautify
xcodebuild -scheme Visor test | xcbeautify
swiftformat . && swiftlint
```
Expected: 0 build warnings; `NewFeaturesTests` passes, which now also covers `islandStackTint`'s default-off since it iterates `NewFeatures.all`.

- [ ] **Step 4: Wire the tint into the front card**

In `NotchRootView.islandSurface`, the fill becomes:

```swift
        shape
            .fill(.black)
            .overlay {
                if frontCardTintEnabled, store.isCardStacked, store.state == .expanded {
                    shape.fill(store.islandPage.tint.opacity(0.18))
                }
            }
```

with `@AppStorage(NewFeatures.islandStackTint.key) private var frontCardTintEnabled = false`.

Note `.home`'s tint is `.clear`, so the player page stays black even with the switch on — which is right: it is the page with no accent of its own.

- [ ] **Step 5: Build and run the full suite again**

```bash
xcodebuild -scheme Visor -configuration Debug build | xcbeautify
xcodebuild -scheme Visor test | xcbeautify
```

- [ ] **Step 6: Commit** (hold until the user asks)

```bash
git add Visor/Support/NewFeatures.swift Visor/App/NewFeaturesView.swift \
        Visor/UI/NotchRootView.swift
git commit -m "feat: paging style picker, tint switch and reveal slider"
```

---

### Task 7: Documentation and hardware checklist

**Files:**
- Modify: `CLAUDE.md` (Progress)
- Modify: `docs/RESEARCH.md`

- [ ] **Step 1: Record it in RESEARCH**

Add a §2.6c beside the existing §2.6b ("one box per page"), covering: depth as the single animated property; why three `NotchShape`s rather than one path; the retract-before-collapse ordering and the `setFrame` bug it avoids; and the measured constants (offset 9, inset 11, radius drop 3).

- [ ] **Step 2: Add a Progress entry**

One entry in CLAUDE.md's Progress list, in the established voice: what shipped, what is behind which key, what is unverified. Keep the file under 200 lines — if it would cross, tighten an older entry rather than dropping this one.

- [ ] **Step 3: Write the hardware checklist**

These cannot be automated. List them for the user:

1. Chins visible below the island ~600ms after it opens, two of them, sizes stepping in.
2. Scrolling down cycles agenda → home → usage → agenda without a dead end.
3. Scrolling up cycles the other way, same absence of a dead end.
4. The agenda chin reads as glass, the usage chin as warm — against both a bright and a dark wallpaper.
5. Closing the island retracts the chins first; **no hard horizontal cut** at the bottom edge mid-close.
6. With the style on Cross-fade, everything is exactly as it was — including the island's height.
7. The reveal slider at 0 shows the chins immediately; at 1500 they take a beat and a half.
8. Stack shows while music plays and the transport row is unmoved.
9. With one page reachable (idle island, paging on), no chins and no extra height.
10. Reduce Motion: the deck does not animate its depth changes.

- [ ] **Step 4: Commit** (hold until the user asks)

```bash
git add CLAUDE.md docs/RESEARCH.md
git commit -m "docs: record the card stack design and its hardware checklist"
```

---

## Self-Review

**Spec coverage:** §1 → Tasks 3, 4 (additive, `covering` untouched). §2 geometry → Task 3 metrics, Task 4 view; the "why three shapes" argument is carried in `IslandStack`'s doc comment. §3 cycling → Task 2, gesture in Task 5. §4 tint → Task 2 (`tint`), Task 4 (chins), Task 6 step 4 (front card). §5 reveal → Task 4; retraction → Task 5. §6 settings → Tasks 1 and 6, with both keys in `ownKeys` at Task 1 step 5. §7 music → no work needed; checklist item 8. §8 tests → Tasks 1, 2, 3. §9 out of scope → nothing built. §10 → checklist items 4 and 5.

**Placeholder scan:** no TBDs; every code step carries the code.

**Type consistency:** `chinReveal`, `IslandStackMetrics.{chinOffset,chinInset,chinRadiusDrop,maxDepth,depths,reveal}`, `isCardStacked`, `stackDepths`, `isStackRetracting`, `turned(by:)`, `cycled(by:in:)`, `usesMaterialChin`, `stackRevealDelay*` are spelled identically at every use.

**Resolved while reviewing:** an earlier draft left the executor a choice between threading `UserDefaults` into `NotchStore` and storing the style on it. Checked — `NotchStore` has no explicit `init` and never reads `UserDefaults`, so the first option would add a dependency the type has deliberately avoided. Task 3 now names the stored-style approach outright, `IslandStackTests` assigns `store.pagingStyle` directly, and Task 6 step 2b keeps that copy in sync with the picker.

**Known risk, accepted:** `NotchRootView.swift` is already long and Task 4 adds two members to it. Task 4 step 5 says to split them into `NotchRootView+Stack.swift` if swiftlint flags the file, following the `SystemCommands+Files.swift` precedent, rather than leaving a new violation standing.
