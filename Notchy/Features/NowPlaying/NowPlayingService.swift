import MediaRemoteAdapter

@MainActor
final class NowPlayingService: NotchService {
    private let store: NotchStore
    private let mediaController = MediaController()
    private let artworkCache = ArtworkCache()

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
        mediaController.stopListening()
        store.setNowPlayingCommands(nil)
        store.setNowPlaying(nil)
        store.deactivate(.nowPlaying)
    }

    private func handle(_ trackInfo: TrackInfo?) {
        guard let payload = trackInfo?.payload, let info = NowPlayingInfo.from(payload) else {
            store.setNowPlaying(nil)
            store.deactivate(.nowPlaying)
            return
        }
        let artwork = artworkCache.image(for: info.trackIdentity, source: payload.artwork)
        store.setNowPlaying(info, artwork: artwork)
        if info.isPlaying {
            store.activate(.nowPlaying)
        } else {
            store.deactivate(.nowPlaying)
        }
    }
}
