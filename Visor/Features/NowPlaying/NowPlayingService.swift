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
        store.nowPlayingCommands = NotchStore.NowPlayingCommands(
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.mediaController.nextTrack() },
            previous: { [weak self] in self?.mediaController.previousTrack() }
        )
        mediaController.startListening()
    }

    func stop() {
        clearTask?.cancel()
        clearTask = nil
        mediaController.stopListening()
        store.nowPlayingCommands = nil
        store.setNowPlaying(nil)
        store.deactivate(.nowPlaying)
    }

    /// Explicit play/pause rather than the adapter's `toggle_play_pause`:
    /// the toggle is one command for two meanings, and players disagree about
    /// what it does when their own state has drifted. We already know whether
    /// the track is playing, so we say which one we want.
    private func togglePlayPause() {
        guard let info = store.nowPlaying else {
            mediaController.togglePlayPause()
            return
        }
        Log.nowPlaying.debug("Transport: \(info.isPlaying ? "pause" : "play")")
        if info.isPlaying {
            mediaController.pause()
        } else {
            mediaController.play()
        }
    }

    private func handle(_ trackInfo: TrackInfo?) {
        guard let payload = trackInfo?.payload, let info = NowPlayingInfo.from(payload) else {
            scheduleClear()
            return
        }
        clearTask?.cancel()
        clearTask = nil
        let artwork = artworkCache.image(for: info.trackIdentity, source: payload.artwork)
        let tint = artworkCache.tint(for: info.trackIdentity)
        let bleed = artworkCache.bleed(for: info.trackIdentity)
        // The adapter re-emits on every position tick. Writing an identical
        // value still notifies @Observable, which re-renders the island for
        // nothing, so compare first.
        let artworkArrived = store.nowPlayingArtwork == nil && artwork != nil
        if info != store.nowPlaying || artworkArrived {
            store.setNowPlaying(info, artwork: artwork, tint: tint, bleed: bleed)
        }
        // Whether a track is loaded, not whether audio is coming out.
        // Deactivating on pause took the transport row away with the layout,
        // so the only way back was the player's own window — and the paused
        // presentation (desaturated art, still bars) had nothing left to draw
        // itself in. A track that actually goes away still clears through
        // `scheduleClear`.
        store.activate(.nowPlaying)
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
