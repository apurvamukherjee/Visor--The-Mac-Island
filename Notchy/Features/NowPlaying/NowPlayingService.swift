import MediaRemoteAdapter

@MainActor
final class NowPlayingService: NotchService {
    private let store: NotchStore
    private let mediaController = MediaController()
    private let artworkCache = ArtworkCache()
    private var clearTask: Task<Void, Never>?

    /// The adapter emits an empty payload between tracks. Clearing on it
    /// makes the expanded view fall back to the idle layout for a few frames
    /// on every skip, so a nil has to survive this long before it counts.
    private static let clearGrace: Duration = .milliseconds(900)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in self?.handle(trackInfo) }
        }
        mediaController.onDecodingError = { error, _ in
            Log.nowPlaying.error("Decoding error: \(error.localizedDescription)")
        }
        store.setNowPlayingCommands(
            NotchStore.NowPlayingCommands(
                togglePlayPause: { [weak self] in self?.mediaController.togglePlayPause() },
                next: { [weak self] in self?.mediaController.nextTrack() },
                previous: { [weak self] in self?.mediaController.previousTrack() }
            )
        )
        mediaController.startListening()
    }

    func stop() {
        clearTask?.cancel()
        clearTask = nil
        mediaController.stopListening()
        store.setNowPlayingCommands(nil)
        store.setNowPlaying(nil)
        store.deactivate(.nowPlaying)
    }

    private func handle(_ trackInfo: TrackInfo?) {
        guard let payload = trackInfo?.payload, let info = NowPlayingInfo.from(payload) else {
            scheduleClear()
            return
        }
        clearTask?.cancel()
        clearTask = nil
        let artwork = artworkCache.image(for: info.trackIdentity, source: payload.artwork)
        store.setNowPlaying(info, artwork: artwork)
        if info.isPlaying {
            store.activate(.nowPlaying)
        } else {
            store.deactivate(.nowPlaying)
        }
    }

    private func scheduleClear() {
        guard clearTask == nil else { return }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.clearGrace, tolerance: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            clearTask = nil
            store.setNowPlaying(nil)
            store.deactivate(.nowPlaying)
        }
    }
}
