import Foundation

/// User-facing switches that outlive a launch. `UserDefaults` directly —
/// there is one of these, and a settings layer for one boolean would be a
/// layer for its own sake.
enum Preferences {
    /// Show a turning record instead of the album cover. Off by default:
    /// the cover is the honest representation of what's playing, and the
    /// record is a preference, not a fallback.
    static let vinylModeKey = "vinylMode"
    /// `MotionPreset.rawValue`. One knob drives every spring in `Motion`.
    static let motionPresetKey = "motionPreset"
    /// `yyyy-MM-dd` of the last wake/login greeting shown, so it fires at
    /// most once a day regardless of how many times the Mac wakes.
    static let lastGreetingDayKey = "lastGreetingDay"
    /// Set once the three-step welcome flow has been shown or dismissed.
    static let hasSeenWelcomeKey = "hasSeenWelcome"
}
