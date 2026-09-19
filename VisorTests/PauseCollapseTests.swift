import Testing
@testable import Visor

/// A paused track collapses the island back to the bare notch, but the track
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

        #expect(store.currentActivity == nil)
        #expect(store.nowPlaying != nil)
        #expect(store.nowPlaying?.isPlaying == false)
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
