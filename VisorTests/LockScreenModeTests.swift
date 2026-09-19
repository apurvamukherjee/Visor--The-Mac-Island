import Testing
@testable import Visor

/// Lock is a *mode*, like onboarding — not one more activity competing in
/// the priority ladder. These guard the seam: nothing about being locked may
/// leak into what the island itself resolves.
@MainActor
struct LockScreenModeTests {
    @Test
    func lockingDoesNotChangeWhichActivityOwnsTheIsland() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        let before = store.expandedKind

        store.isLocked = true
        store.isLockTransitioning = true

        #expect(store.expandedKind == before)
        #expect(store.currentActivity?.kind == .nowPlaying)
    }

    /// The padlock is a compact activity, the way the reference has it —
    /// `LockScreenNotchContent` with its own priority. What must not happen
    /// is it claiming the *expanded* island: it is a wing, not a panel.
    @Test
    func theLockWingNeverOwnsTheExpandedIsland() {
        #expect(resolveExpandedKind([.lock: Activity(kind: .lock)]) == nil)
    }

    /// And it outranks everything else in the wings: while the screen is
    /// locked, nothing else about the machine is the headline.
    @Test
    func theLockWingOutranksEveryOtherPeek() {
        let active: [ActivityKind: Activity] = [
            .lock: Activity(kind: .lock),
            .nowPlaying: Activity(kind: .nowPlaying),
            .screenshot: Activity(kind: .screenshot)
        ]
        #expect(resolveCurrentActivity(active)?.kind == .lock)
    }

    /// The bug this guards: the lock-screen panel used to be gated on the
    /// unlock *settle* as well, so it stayed on screen for most of a second
    /// after the desktop was already back. The settle is for the padlock's
    /// own animation, which plays over the desktop — nothing drawn on the
    /// lock screen may read it.
    @Test
    func nothingIsPresentedOnTheLockScreenOnceItUnlocks() {
        let store = NotchStore()
        store.isLocked = true
        #expect(store.isLockPresenting)

        store.isLocked = false
        // Still true: the padlock is still animating open over the desktop.
        store.isLockTransitioning = true
        #expect(!store.isLockPresenting)
    }

    /// The pre-lock edge is what puts the padlock up *before* the shield
    /// lands, so it has to count as presenting.
    @Test
    func thePreLockEdgeCountsAsPresenting() {
        let store = NotchStore()
        store.isPreparingLock = true
        #expect(store.isLockPresenting)

        // A session that goes active again without ever locking clears it.
        store.isPreparingLock = false
        #expect(!store.isLockPresenting)
    }
}

/// Swiping an activity away hides it without ending it — the feature still
/// owns its activity, the user has just asked not to look at it.
@MainActor
struct SwipeDismissTests {
    @Test
    func dismissingHidesTheCurrentActivityButLeavesItActive() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        store.dismissCurrentActivity()

        #expect(store.currentActivity == nil)
        #expect(store.expandedKind == nil)
        // Still active: the service was never told to stop.
        #expect(store.activities[.nowPlaying] != nil)
    }

    @Test
    func restoringBringsItBack() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        store.dismissCurrentActivity()
        store.restoreDismissedActivity()

        #expect(store.currentActivity?.kind == .nowPlaying)
    }

    /// A dismissal must not swallow the *next* thing to happen — only the
    /// one that was swiped away.
    @Test
    func somethingElseStartingIsStillShown() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        store.dismissCurrentActivity()
        store.activate(.screenshot)

        #expect(store.currentActivity?.kind == .screenshot)
    }

    /// Once the dismissed activity ends, the dismissal must stop applying —
    /// otherwise the next track would silently never appear.
    @Test
    func theDismissalLapsesWhenThatActivityEnds() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        store.dismissCurrentActivity()
        store.deactivate(.nowPlaying)
        store.activate(.nowPlaying)

        #expect(store.currentActivity?.kind == .nowPlaying)
    }
}
