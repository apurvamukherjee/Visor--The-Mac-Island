import Foundation
import MediaRemoteAdapter

@MainActor
final class NowPlayingService: NotchService {
    private let store: NotchStore
    private let mediaController = MediaController()
    private let artworkCache = ArtworkCache()
    private var clearTask: Task<Void, Never>?
    private var pauseCollapseTask: Task<Void, Never>?

    /// The adapter emits an empty payload between tracks. Clearing on it
    /// makes the expanded view fall back to the idle layout for a few frames
    /// on every skip, so a nil has to survive this long before it counts.
    private static let clearGrace: Duration = .milliseconds(900)

    /// How long a track stays on the island after it is paused. Ported from
    /// the reference's pause-hide timer, which uses the same 5s.
    ///
    /// It is a delay rather than an immediate collapse because a pause is
    /// very often a step on the way to something else — skipping, seeking,
    /// answering a call — and an island that shuts the instant the music
    /// stops flaps open and closed around every one of those.
    private static let pauseCollapseDelay: Duration = .seconds(5)

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
            previous: { [weak self] in self?.mediaController.previousTrack() },
            seek: { [weak self] seconds in self?.mediaController.setTime(seconds: seconds) },
            toggleShuffle: { [weak self] in self?.cycleShuffle() },
            cycleRepeat: { [weak self] in self?.cycleRepeat() }
        )
        mediaController.startListening()
    }

    func stop() {
        clearTask?.cancel()
        clearTask = nil
        pauseCollapseTask?.cancel()
        pauseCollapseTask = nil
        mediaController.stopListening()
        store.nowPlayingCommands = nil
        store.setNowPlaying(nil)
        store.nowPlayingProgress = nil
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
        syncPresence(isPlaying: info.isPlaying)
        updateProgress(from: payload)
    }

    /// Only written on a real event — see `NowPlayingProgress.shouldReplace`
    /// — so the scrub bar can exist without the store rewrite this file's
    /// own history already paid to remove once.
    private func updateProgress(from payload: TrackInfo.Payload) {
        guard let durationMicros = payload.durationMicros, durationMicros > 0,
              let elapsedMicros = payload.elapsedTimeMicros,
              let timestampMicros = payload.timestampEpochMicros
        else {
            store.nowPlayingProgress = nil
            return
        }
        let isPlaying = payload.isPlaying ?? false
        let incoming = NowPlayingProgress(
            duration: durationMicros / 1_000_000,
            elapsedAtAnchor: elapsedMicros / 1_000_000,
            anchorDate: Date(timeIntervalSince1970: timestampMicros / 1_000_000),
            isPlaying: isPlaying,
            rate: payload.playbackRate ?? (isPlaying ? 1 : 0)
        )
        if NowPlayingProgress.shouldReplace(store.nowPlayingProgress, with: incoming) {
            store.nowPlayingProgress = incoming
        }
    }

    /// Explicit target mode rather than a blind toggle, for the same reason
    /// `togglePlayPause` picks a direction instead of calling the adapter's
    /// own toggle: we already know the current mode.
    private func cycleShuffle() {
        let next: TrackInfo.ShuffleMode = (store.nowPlaying?.shuffleMode ?? .off) == .off ? .songs : .off
        mediaController.setShuffleMode(next)
    }

    private func cycleRepeat() {
        let next: TrackInfo.RepeatMode = switch store.nowPlaying?.repeatMode ?? .off {
        case .off: .all
        case .all: .one
        case .one: .off
        }
        mediaController.setRepeatMode(next)
    }

    /// Playing shows the island; paused collapses it back to the bare notch
    /// after `pauseCollapseDelay`.
    ///
    /// The track itself is deliberately **not** cleared — only the activity
    /// is deactivated. `store.nowPlaying` stays loaded, so the transport row
    /// is still there the moment the island is opened by hand, and the lock
    /// screen's cached track survives. A track that actually goes away is a
    /// different event and still clears through `scheduleClear`.
    private func syncPresence(isPlaying: Bool) {
        guard !isPlaying else {
            pauseCollapseTask?.cancel()
            pauseCollapseTask = nil
            store.activate(.nowPlaying)
            return
        }
        // Already counting down, or already collapsed: the adapter re-emits
        // on a position tick, so re-arming here would push the deadline out
        // forever and the island would never collapse.
        guard pauseCollapseTask == nil, store.isActive(.nowPlaying) else { return }
        pauseCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pauseCollapseDelay, tolerance: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            pauseCollapseTask = nil
            guard store.nowPlaying?.isPlaying == false else { return }
            store.deactivate(.nowPlaying)
        }
    }

    private func scheduleClear() {
        guard clearTask == nil else { return }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.clearGrace, tolerance: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            clearTask = nil
            pauseCollapseTask?.cancel()
            pauseCollapseTask = nil
            store.setNowPlaying(nil)
            store.nowPlayingProgress = nil
            store.deactivate(.nowPlaying)
        }
    }
}
