import MediaRemoteAdapter

/// Only what the island draws. Playback position used to live here too, and
/// since the adapter re-emits it constantly, every position tick rewrote the
/// store and re-rendered the whole island for a value nothing displayed.
/// Equatable is load-bearing: `NowPlayingService` compares before writing.
struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String?
    let isPlaying: Bool
    /// Cache key for artwork — changes only when the actual track changes.
    let trackIdentity: String
    /// Which app is playing, so clicking the artwork can bring it forward.
    /// Nil when the adapter does not report one.
    let bundleIdentifier: String?
    /// Safe to compare unlike elapsed/timestamp: a player only changes these
    /// on a real toggle, not on every position tick.
    let shuffleMode: TrackInfo.ShuffleMode
    let repeatMode: TrackInfo.RepeatMode

    static func from(_ payload: TrackInfo.Payload) -> NowPlayingInfo? {
        guard let title = payload.title else { return nil }
        let isPlaying = payload.isPlaying ?? false
        return NowPlayingInfo(
            title: title,
            artist: payload.artist,
            isPlaying: isPlaying,
            trackIdentity: "\(payload.bundleIdentifier ?? ""):\(title):\(payload.artist ?? "")",
            bundleIdentifier: payload.bundleIdentifier,
            shuffleMode: payload.shuffleMode ?? .off,
            repeatMode: payload.repeatMode ?? .off
        )
    }
}
