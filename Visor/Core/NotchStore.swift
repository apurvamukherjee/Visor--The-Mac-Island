import CoreGraphics
import Foundation
import Observation
import SwiftUI

enum NotchState: Equatable, Sendable {
    case closed
    case expanded
    case compact
}

@Observable
@MainActor
final class NotchStore {
    struct ScreenshotCommands {
        let adopt: (URL) -> Void
    }

    struct NowPlayingCommands {
        let togglePlayPause: () -> Void
        let next: () -> Void
        let previous: () -> Void
    }

    var state: NotchState = .closed
    var closedSize: CGSize = .zero
    var battery: BatteryInfo?
    var nowPlayingCommands: NowPlayingCommands?
    var screenshotCommands: ScreenshotCommands?
    /// True while a file is being dragged over the island. The window
    /// controller watches it so the island opens to meet the drag.
    var isDropTargeted = false
    var calendarEvents: [CalendarEvent] = []

    /// These three keep their setters because the setters do something:
    /// `activate`/`deactivate` own the dictionary's shape, and `setNowPlaying`
    /// keeps the track and its artwork in step.
    private(set) var activities: [ActivityKind: Activity] = [:]
    private(set) var nowPlaying: NowPlayingInfo?
    private(set) var nowPlayingArtwork: CGImage?
    private(set) var nowPlayingTint: Color?
    private(set) var screenshot: ScreenshotCatch?

    var currentActivity: Activity? {
        resolveCurrentActivity(activities)
    }

    /// Both guard before mutating: assigning an equal value still fires an
    /// `@Observable` notification, and these are called on every adapter and
    /// power event, most of which change nothing.
    func activate(_ kind: ActivityKind) {
        guard activities[kind] == nil else { return }
        activities[kind] = Activity(kind: kind)
    }

    func deactivate(_ kind: ActivityKind) {
        guard activities[kind] != nil else { return }
        activities.removeValue(forKey: kind)
    }

    /// Track, artwork and tint move together — a separate write for the tint
    /// would leave a frame where new artwork wears the previous colour.
    func setNowPlaying(_ info: NowPlayingInfo?, artwork: CGImage? = nil, tint: Color? = nil) {
        nowPlaying = info
        nowPlayingArtwork = artwork
        nowPlayingTint = tint
    }

    func setScreenshot(_ shot: ScreenshotCatch?) {
        guard shot != screenshot else { return }
        screenshot = shot
        if shot == nil {
            deactivate(.screenshot)
        } else {
            activate(.screenshot)
        }
    }
}
