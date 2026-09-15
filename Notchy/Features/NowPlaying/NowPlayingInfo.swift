import Foundation
import MediaRemoteAdapter

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String?
    let isPlaying: Bool
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
    let timestamp: Date
    let playbackRate: Double
    /// Cache key for artwork — changes only when the actual track changes.
    let trackIdentity: String

    static func from(_ payload: TrackInfo.Payload) -> NowPlayingInfo? {
        guard let title = payload.title else { return nil }
        let isPlaying = payload.isPlaying ?? false
        return NowPlayingInfo(
            title: title,
            artist: payload.artist,
            isPlaying: isPlaying,
            elapsedTime: (payload.elapsedTimeMicros ?? 0) / 1_000_000,
            duration: payload.durationMicros.map { $0 / 1_000_000 },
            timestamp: payload.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? .now,
            playbackRate: payload.playbackRate ?? (isPlaying ? 1 : 0),
            trackIdentity: "\(payload.bundleIdentifier ?? ""):\(title):\(payload.artist ?? "")"
        )
    }
}
