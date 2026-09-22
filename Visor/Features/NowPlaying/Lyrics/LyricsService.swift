import Foundation
import Observation

/// Fetches lyrics, and only while somebody is looking at them.
///
/// The gate is the whole design: a track playing with the panel shut never
/// makes a network request, so leaving music on all day costs nothing. The
/// observation is one-shot and re-arms itself, the same pattern
/// `NotchWindowController` uses — no polling, nothing running while the
/// panel is closed.
@MainActor
final class LyricsService: NotchService {
    private let store: NotchStore
    private var fetchTask: Task<Void, Never>?
    /// What `store.lyrics` currently holds, so re-opening the panel on the
    /// same track does not fetch it again.
    private var fetchedIdentity: String?

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        observe()
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        fetchedIdentity = nil
        store.lyrics = nil
        store.isLyricsOpen = false
    }

    private func observe() {
        withObservationTracking {
            _ = store.isLyricsOpen
            _ = store.nowPlaying?.trackIdentity
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleChange() }
        }
    }

    private func handleChange() {
        observe()
        guard store.isLyricsOpen, let info = store.nowPlaying else {
            fetchTask?.cancel()
            fetchTask = nil
            fetchedIdentity = nil
            store.lyrics = nil
            return
        }
        guard info.trackIdentity != fetchedIdentity else { return }

        fetchedIdentity = info.trackIdentity
        store.lyrics = nil
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            let result = await LyricsFetcher.fetch(title: info.title, artist: info.artist)
            guard !Task.isCancelled, let self else { return }
            // The track can change while the request is in flight; a late
            // answer for the previous song is worse than none.
            guard store.nowPlaying?.trackIdentity == info.trackIdentity else { return }
            store.lyrics = result
        }
    }
}
