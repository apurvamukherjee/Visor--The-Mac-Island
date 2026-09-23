import Foundation

/// How long each transient thing the island shows stays up.
///
/// Thirteen sleeps across nine services, and left to themselves they drifted
/// to ten different numbers for the same job — the drift `IslandSpacing`
/// exists to prevent, in the time dimension. Same medicine: one file, so the
/// spread is visible at a glance instead of scattered one literal per
/// service where nobody can see two of them at once.
///
/// **One constant per site, named for the site — deliberately not three
/// tiers.** Collapsing these to `acknowledge`/`read`/`alert` would change
/// seven of them, and the rule for this whole feature program is that
/// nothing changes until someone asks for it. Every value below is exactly
/// what that service already used. Tiering them is Phase 8's job, at the
/// point where the timing becomes a knob and moving a value is the point.
enum Dwell {
    /// The wave easter egg.
    static let wave: Duration = .seconds(1.2)
    /// A volume nudge is acknowledged, not read — the shortest of the lot.
    static let volume: Duration = .seconds(1.6)
    static let focus: Duration = .seconds(2)
    /// How long a caught screenshot survives the pointer leaving it. While
    /// the island is open the user is looking at the catch, so the countdown
    /// restarts rather than pulling it out from under them.
    static let screenshotHoverGrace: Duration = .seconds(2)
    /// The charging peek.
    static let battery: Duration = .seconds(2.5)
    static let bluetooth: Duration = .seconds(3)
    /// How long a finished AirDrop stays on screen.
    static let airDropLinger: Duration = .seconds(3)
    static let greeting: Duration = .seconds(3.5)
    /// An accessory's charge, peeked on connection only. Long enough to
    /// read a glyph and a figure and look away — 2.5 was the original and
    /// read as a flash once the wing started carrying a device name.
    static let deviceBattery: Duration = .seconds(4)
    /// How long a finished download stays on screen.
    static let downloadLinger: Duration = .seconds(4)
    /// How long a track stays on the island after it is paused, ported from
    /// the reference's pause-hide timer, which uses the same 5s. A delay
    /// rather than an immediate collapse because a pause is very often a
    /// step on the way to something else — skipping, seeking, answering a
    /// call — and an island that shuts the instant the music stops flaps
    /// open and closed around every one of those.
    static let pauseCollapse: Duration = .seconds(5)
    /// Low and full battery. Longer than the plug/unplug peek because an
    /// alert is meant to be read, not just noticed.
    static let batteryAlert: Duration = .seconds(6)
    /// A finished timer, the longest — it is the only one that is asking
    /// for something back.
    static let timerFinishedLinger: Duration = .seconds(8)
    /// How long after the island settles the chins slide out. The default
    /// behind `Preferences.stackRevealDelay`, which a slider overrides —
    /// this is the number that ships, not the one that is read.
    static let stackReveal: Duration = .milliseconds(600)
    /// How long the chins take to retract before the island collapses.
    /// Load-bearing, not styling: the frame must never be smaller than what
    /// is drawn. See `NotchWindowController.collapseFromExpanded`.
    static let stackRetract: Duration = .milliseconds(120)
}
