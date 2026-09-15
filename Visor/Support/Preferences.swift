import Foundation

/// User-facing switches that outlive a launch. `UserDefaults` directly —
/// there is one of these, and a settings layer for one boolean would be a
/// layer for its own sake.
enum Preferences {
    /// Show a turning record instead of the album cover. Off by default:
    /// the cover is the honest representation of what's playing, and the
    /// record is a preference, not a fallback.
    static let vinylModeKey = "vinylMode"
}
