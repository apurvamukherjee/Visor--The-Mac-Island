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

    struct TimerCommands {
        let start: (TimeInterval) -> Void
        let togglePause: () -> Void
        let cancel: () -> Void
    }

    struct VolumeCommands {
        let setLevel: (Float) -> Void
        let toggleMute: () -> Void
    }

    struct NetworkCommands {
        let dismiss: () -> Void
    }

    struct NowPlayingCommands {
        let togglePlayPause: () -> Void
        let next: () -> Void
        let previous: () -> Void
        let seek: (TimeInterval) -> Void
        let toggleShuffle: () -> Void
        let cycleRepeat: () -> Void
    }

    struct AirDropCommands {
        let send: ([URL]) -> Void
        let dismiss: () -> Void
    }

    struct OnboardingCommands {
        let advance: () -> Void
        let finish: () -> Void
        let replay: () -> Void
    }

    var state: NotchState = .closed
    var closedSize: CGSize = .zero
    var battery: BatteryInfo?
    /// Bumped by `BatteryService` on either edge of the charging transition,
    /// so the compact glyph's bounce is driven by the actual event rather
    /// than inferred from view-mount timing — which broke down once the
    /// glyph could also appear for reasons that have nothing to do with
    /// charging (a screenshot catch, the wave, the greeting).
    var batteryBounceTick = 0
    var nowPlayingCommands: NowPlayingCommands?
    /// Anchor-based, not live — written only on a real event. See
    /// `NowPlayingProgress` for why.
    var nowPlayingProgress: NowPlayingProgress?
    var networkCommands: NetworkCommands?
    /// Set by `NetworkService`; the `.network` activity follows it, except
    /// while the user has dismissed the alert for this offline episode.
    var isOffline = false
    /// Set and cleared by `BatteryService`, which owns the alert's lifetime
    /// the same way it owns the charging peek's.
    var batteryAlert: BatteryAlert?
    /// Set and cleared by `DeviceBatteryService`, which owns the peek's
    /// lifetime the way `BatteryService` owns the charging one's.
    var deviceBattery: DeviceBattery?
    var volumeCommands: VolumeCommands?
    /// Owned by `VolumeService`, which also owns `.volume`'s peek.
    var volume: VolumeInfo?
    var timerCommands: TimerCommands?
    /// Owned by `TimerService`. Stored as a deadline, so nothing ticks to
    /// keep it true — see `IslandTimer`.
    var timer: IslandTimer?
    var screenshotCommands: ScreenshotCommands?
    /// True while a file is being dragged over the island. The window
    /// controller watches it so the island opens to meet the drag.
    var isDropTargeted = false
    /// Cursor position inside the island as (-1...1) on both axes, or nil
    /// when the pointer is away. Only written while expanded.
    var hoverPoint: CGPoint?
    var calendarEvents: [CalendarEvent] = []
    /// Additive displacement of the island's resting size, driven by the
    /// collapse squash. Written only by `NotchWindowController`, and back to
    /// zero every time — nothing rests on a non-zero value.
    var squashWidth: CGFloat = 0
    var squashHeight: CGFloat = 0
    /// 0...1 while a two-finger swipe is in progress. The island squeezes
    /// and its content recedes in proportion, so the gesture has something
    /// to push against instead of firing blind at the threshold.
    var swipeProgress: CGFloat = 0
    /// Set and cleared by `GreetingService`, which also owns `.greeting`'s
    /// activation/dismissal — same split as `battery`, whose peek is likewise
    /// driven by its service rather than the store.
    var greetingText: Greeting?
    /// Owned by `OnboardingService`. Non-nil means the welcome flow is
    /// showing, which overrides the normal activity ladder outright rather
    /// than competing inside it — see `layout` and `expandedKind` below.
    var onboardingStep: OnboardingStep?
    var onboardingCommands: OnboardingCommands?

    // MARK: - Lock screen

    //
    // Lock is a *mode*, like onboarding and like `state` itself — not one
    // more activity competing in the priority ladder. The island's own panel
    // is deliberately pinned below the lock shield and stays there; these
    // drive a separate pair of overlay panels that live above it. See
    // `LockScreenService`.

    /// Set by `LockScreenService`. True from the moment the screen locks
    /// until it unlocks.
    var isLocked = false
    /// True while a lock or unlock is still animating, including the
    /// fast-user-switch edge before the shield actually appears. The overlay
    /// outlives `isLocked` by this much so the unlock animation can finish
    /// instead of being cut off.
    var isLockTransitioning = false

    // MARK: - Ported live activities

    /// Owned by `DownloadService`. Empty means nothing is arriving.
    var downloads: [DownloadItem] = []
    /// Owned by `AirDropService`; outgoing sends only.
    var airDropTransfer: AirDropTransfer?
    var airDropCommands: AirDropCommands?
    /// Owned by `ScreenRecordingService`. Holds a start date, not a
    /// ticking elapsed value — see `ScreenRecording`.
    var screenRecording: ScreenRecording?
    /// Owned by `BluetoothService`; an event, so it clears itself.
    var bluetoothAlert: BluetoothAlert?
    /// Owned by `FocusService`. `isFocusOn` is the condition; `focusPeek`
    /// is the transient announcement of it changing, which is what drives
    /// the `.focus` activity.
    var isFocusOn = false
    var focusPeek: Bool?
    /// Owned by `NetworkService`. Non-nil means a VPN is actually up — see
    /// `VPNStatus` for why that is not the same as a `utun` interface
    /// existing.
    var vpnName: String?
    /// True when the island is drawing on a screen with no physical cutout,
    /// where it becomes a free-floating capsule. Written by
    /// `NotchWindowController` whenever it resolves its target screen.
    var isCapsule = false
    /// The user's width/height trim from Settings, in points. Applied as a
    /// delta on the measured cutout the same way every layout is.
    var notchWidthOffset: CGFloat = 0
    var notchHeightOffset: CGFloat = 0
    /// Set by a swipe-up on the island: the current activity is hidden until
    /// it goes away on its own or a swipe-down brings it back. Not a
    /// `deactivate` — the feature still owns its activity, the user has just
    /// asked not to look at it.
    var dismissedActivity: ActivityKind?

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
    /// Newest first. A shelf rather than a single catch: screenshots
    /// arrive in bursts, and the old model threw the previous one away
    /// mid-glance.
    private(set) var shelf: [ScreenshotCatch] = []
    private var waveTask: Task<Void, Never>?

    private static let waveDuration: TimeInterval = 1.2
    /// Past this the row stops fitting the island and the oldest is dropped.
    static let shelfLimit = 4

    var currentActivity: Activity? {
        resolveCurrentActivity(visibleActivities)
    }

    /// Everything active except whatever the user swiped away.
    private var visibleActivities: [ActivityKind: Activity] {
        guard let dismissedActivity else { return activities }
        return activities.filter { $0.key != dismissedActivity }
    }

    /// True while the welcome flow owns the island. `NotchWindowController`
    /// consults this to force-expand and to suspend the normal hover-out
    /// collapse, and `GreetingService` to skip a peek nobody would see.
    var isOnboardingActive: Bool {
        onboardingStep != nil
    }

    /// The feature that owns the expanded island, or nil for the idle
    /// agenda. Read by both the layout and the view, so they cannot drift.
    var expandedKind: ActivityKind? {
        resolveExpandedKind(visibleActivities)
    }

    /// Swipe up: hide whatever owns the island right now.
    func dismissCurrentActivity() {
        guard let kind = currentActivity?.kind else { return }
        dismissedActivity = kind
    }

    /// Swipe down: undo that.
    func restoreDismissedActivity() {
        guard dismissedActivity != nil else { return }
        dismissedActivity = nil
    }

    /// Bumped by Settings whenever a notch trim moves, so the window
    /// controller can re-measure. A counter rather than the values
    /// themselves: the controller wants "something changed, re-read the
    /// screen", and two values would have it re-measuring twice for one drag.
    private(set) var notchSizeTick = 0

    func previewNotchSize() {
        notchSizeTick += 1
    }

    /// The shape the island takes right now. Onboarding is checked first and
    /// unconditionally: it is not one more activity competing in the
    /// priority ladder, it is a different mode the island is in, the same
    /// way `state` is.
    var layout: IslandLayout {
        if let onboardingStep {
            return IslandLayout.onboarding(onboardingStep)
        }
        return IslandLayout.resolved(for: expandedKind, content: islandContent)
    }

    /// Filtered exactly the way the agenda view filters, so the island can
    /// never reserve a row for an event that has already ended.
    var islandContent: IslandContent {
        let upcoming = CalendarEventMapper.upcomingCount(calendarEvents, now: .now)
        return IslandContent(
            agendaRows: min(upcoming, IslandLayout.maxEventRows),
            hasAgendaOverflow: upcoming > IslandLayout.maxEventRows,
            hasTimerPresets: timerCommands != nil,
            downloadRows: min(downloads.count, IslandLayout.maxDownloadRows)
        )
    }

    /// True while either lock overlay should be on screen. It stays true
    /// through the unlock animation, which is why it is not just `isLocked`.
    var isLockPresenting: Bool {
        isLocked || isLockTransitioning
    }

    /// The island's resting size for the current state, before the squash
    /// and swipe offsets are applied.
    func restingSize(for state: NotchState) -> CGSize {
        switch state {
        case .expanded: layout.expandedSize(closed: closedSize)
        case .compact: layout.compactSize(closed: closedSize)
        case .closed: closedSize
        }
    }

    /// True while the double-click easter egg's peek is showing.
    var wave: Bool {
        activities[.wave] != nil
    }

    /// The idle-island double-click easter egg. No-ops over any real
    /// activity — it only ever fires into a genuinely empty island. Owns its
    /// own dismiss timer directly, the way `BatteryService.schedulePeek`
    /// does, since there is no external resource behind it that would need a
    /// full `NotchService` to release.
    func triggerWave() {
        guard currentActivity == nil else { return }
        Haptics.wave()
        activate(.wave)
        waveTask?.cancel()
        waveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.waveDuration), tolerance: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.deactivate(.wave)
        }
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
        // The dismissal dies with the thing it dismissed. Left standing, the
        // *next* activity of the same kind would be silently swallowed — a
        // track swiped away would take every track after it.
        if dismissedActivity == kind {
            dismissedActivity = nil
        }
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

    /// Newest first, capped. Re-adding a catch already on the shelf is a
    /// no-op rather than a duplicate row.
    func addToShelf(_ item: ScreenshotCatch) {
        guard !shelf.contains(item) else { return }
        shelf.insert(item, at: 0)
        if shelf.count > Self.shelfLimit {
            shelf.removeLast(shelf.count - Self.shelfLimit)
        }
        activate(.screenshot)
    }

    /// Removes only if it is still on the shelf. A drag provider outlives
    /// the chip that created it — the receiver can load it after the shelf
    /// has moved on — so an unconditional removal there would throw away
    /// whatever the user is currently looking at.
    func removeFromShelf(_ item: ScreenshotCatch) {
        guard let index = shelf.firstIndex(of: item) else { return }
        shelf.remove(at: index)
        if shelf.isEmpty {
            deactivate(.screenshot)
        }
    }

    func clearShelf() {
        guard !shelf.isEmpty else { return }
        shelf.removeAll()
        deactivate(.screenshot)
    }
}
