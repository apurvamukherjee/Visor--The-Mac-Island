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

    private(set) var state: NotchState = .closed
    private(set) var closedSize: CGSize = .zero
    private(set) var activities: [ActivityKind: Activity] = [:]
    private(set) var battery: BatteryInfo?
    private(set) var nowPlaying: NowPlayingInfo?
    private(set) var nowPlayingArtwork: CGImage?
    private(set) var nowPlayingCommands: NowPlayingCommands?
    private(set) var calendarEvents: [CalendarEvent] = []

    var currentActivity: Activity? {
        resolveCurrentActivity(activities)
    }

    func setState(_ newState: NotchState) {
        state = newState
    }

    func setClosedSize(_ size: CGSize) {
        closedSize = size
    }

    func activate(_ kind: ActivityKind, expiresAt: Date? = nil) {
        activities[kind] = Activity(kind: kind, expiresAt: expiresAt)
    }

    func deactivate(_ kind: ActivityKind) {
        activities.removeValue(forKey: kind)
    }

    func setBattery(_ info: BatteryInfo) {
        battery = info
    }

    func setNowPlaying(_ info: NowPlayingInfo?, artwork: CGImage? = nil) {
        nowPlaying = info
        nowPlayingArtwork = artwork
    }

    func setNowPlayingCommands(_ commands: NowPlayingCommands?) {
        nowPlayingCommands = commands
    }

    func setCalendarEvents(_ events: [CalendarEvent]) {
        calendarEvents = events
    }
}
