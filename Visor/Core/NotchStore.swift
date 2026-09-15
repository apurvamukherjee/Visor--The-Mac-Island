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
    /// Cursor position inside the island as (-1...1) on both axes, or nil
    /// when the pointer is away. Only written while expanded.
    var hoverPoint: CGPoint?
    var calendarEvents: [CalendarEvent] = []

    /// These three keep their setters because the setters do something:
    /// `activate`/`deactivate` own the dictionary's shape, and `setNowPlaying`
    /// keeps the track and its artwork in step.
    private(set) var activities: [ActivityKind: Activity] = [:]
    private(set) var nowPlaying: NowPlayingInfo?
    private(set) var nowPlayingArtwork: CGImage?
    private(set) var nowPlayingTint: Color?
    /// The blurred backdrop for the expanded music layout. Separate from
    /// `nowPlayingArtwork` because it is built once per track and read by a
    /// different view.
    private(set) var nowPlayingBleed: CGImage?
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

    /// Track, artwork, tint and backdrop move together — a separate write for
    /// any of them would leave a frame where new artwork wears the previous
    /// colour.
    func setNowPlaying(
        _ info: NowPlayingInfo?,
        artwork: CGImage? = nil,
        tint: Color? = nil,
        bleed: CGImage? = nil
    ) {
        nowPlaying = info
        nowPlayingArtwork = artwork
        nowPlayingTint = tint
        nowPlayingBleed = bleed
    }

    /// Clears the catch only if it is still the one named. A drag provider
    /// outlives the chip that created it — the receiver can load it after a
    /// newer screenshot has taken the wing — and an unconditional clear there
    /// would throw away the catch the user is currently looking at.
    func dismissScreenshot(_ shot: ScreenshotCatch) {
        guard screenshot == shot else { return }
        setScreenshot(nil)
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
