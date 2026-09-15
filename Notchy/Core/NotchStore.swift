import CoreGraphics
import Foundation
import Observation

enum NotchState: Equatable, Sendable {
    case closed
    case expanded
    case compact
}

@Observable
@MainActor
final class NotchStore {
    struct NowPlayingCommands {
        let togglePlayPause: () -> Void
        let next: () -> Void
        let previous: () -> Void
    }

    var state: NotchState = .closed
    var closedSize: CGSize = .zero
    var battery: BatteryInfo?
    var nowPlayingCommands: NowPlayingCommands?
    var calendarEvents: [CalendarEvent] = []

    /// These three keep their setters because the setters do something:
    /// `activate`/`deactivate` own the dictionary's shape, and `setNowPlaying`
    /// keeps the track and its artwork in step.
    private(set) var activities: [ActivityKind: Activity] = [:]
    private(set) var nowPlaying: NowPlayingInfo?
    private(set) var nowPlayingArtwork: CGImage?

    var currentActivity: Activity? {
        resolveCurrentActivity(activities)
    }

    func activate(_ kind: ActivityKind) {
        activities[kind] = Activity(kind: kind)
    }

    func deactivate(_ kind: ActivityKind) {
        activities.removeValue(forKey: kind)
    }

    func setNowPlaying(_ info: NowPlayingInfo?, artwork: CGImage? = nil) {
        nowPlaying = info
        nowPlayingArtwork = artwork
    }
}
