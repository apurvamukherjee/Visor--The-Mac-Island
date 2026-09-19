import Testing
@testable import Visor

/// A paused track collapses the island down to a single dot, but the track
/// itself stays loaded — see `NowPlayingService.syncPresence`.
///
/// The 5s delay lives in a `Task.sleep`, so what is pinned here is the seam
/// the collapse rests on rather than the timer: deactivating `.nowPlaying`
/// must take the island away *without* taking the track with it, because the
/// transport row is how playback gets started again.
@MainActor
struct PauseCollapseTests {
    private func pausedTrack() -> NowPlayingInfo {
        NowPlayingInfo(
            title: "Perfect",
            artist: "Ed Sheeran",
            isPlaying: false,
            trackIdentity: "test:Perfect:Ed Sheeran",
            bundleIdentifier: nil,
            shuffleMode: .off,
            repeatMode: .off
        )
    }

    /// The whole point of collapsing rather than clearing: open the island by
    /// hand after it has collapsed and the player is still there to press
    /// play on.
    @Test
    func collapsingKeepsTheTrackLoaded() {
        let store = NotchStore()
        store.setNowPlaying(pausedTrack())
        store.activate(.nowPlaying)

        store.deactivate(.nowPlaying)
        store.activate(.pausedTrack)

        #expect(store.currentActivity?.kind == .pausedTrack)
        #expect(store.nowPlaying != nil)
        #expect(store.nowPlaying?.isPlaying == false)
    }

    /// The dot is the handle back to the player: hovering it has to resolve
    /// to the same expanded card, or there is nothing to press play on.
    @Test
    func thePausedDotStillOpensThePlayer() {
        let store = NotchStore()
        store.setNowPlaying(pausedTrack())
        store.activate(.pausedTrack)

        #expect(store.expandedKind == .pausedTrack)
        #expect(
            IslandLayout.resolved(for: .pausedTrack, content: .empty).expandedExtraWidth
                == IslandLayout.nowPlaying(.empty).expandedExtraWidth
        )
    }

    /// The dot must never outrank a real activity, and must never sit beside
    /// `.nowPlaying` — resuming hands the wing back.
    @Test
    func thePausedDotYieldsToRealActivities() {
        let store = NotchStore()
        store.activate(.pausedTrack)
        store.activate(.download)

        #expect(store.currentActivity?.kind == .download)
    }

    /// Resuming re-activates rather than re-loading, so the island comes back
    /// without the track having gone anywhere.
    @Test
    func resumingBringsTheIslandBack() {
        let store = NotchStore()
        store.setNowPlaying(pausedTrack())
        store.activate(.nowPlaying)
        store.deactivate(.nowPlaying)

        store.activate(.nowPlaying)

        #expect(store.currentActivity?.kind == .nowPlaying)
    }

    /// `syncPresence` re-arms only when the island is still up. Without this
    /// the adapter's position ticks would push the deadline out forever and
    /// a paused track would never collapse.
    @Test
    func isActiveReportsWhetherTheIslandIsStillUp() {
        let store = NotchStore()
        #expect(!store.isActive(.nowPlaying))

        store.activate(.nowPlaying)
        #expect(store.isActive(.nowPlaying))

        store.deactivate(.nowPlaying)
        #expect(!store.isActive(.nowPlaying))
    }
}
