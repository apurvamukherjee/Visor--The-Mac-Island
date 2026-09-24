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
