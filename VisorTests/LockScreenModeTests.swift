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

    @Test
    func lockIsNotAnActivityKind() {
        // If lock ever became an ActivityKind this stops compiling, which is
        // the point: the ladder and the mode must stay separate.
        #expect(!ActivityKind.allCases.contains { "\($0)".lowercased().contains("lock") })
    }

    /// The overlay outlives the unlock so its animation can finish — which
    /// is why the presenting flag is not just `isLocked`.
    @Test
    func theOverlayStaysPresentingThroughTheUnlockAnimation() {
        let store = NotchStore()
        store.isLocked = true
        store.isLockTransitioning = true
        #expect(store.isLockPresenting)

        store.isLocked = false
        #expect(store.isLockPresenting)

        store.isLockTransitioning = false
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
