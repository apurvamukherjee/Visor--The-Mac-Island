import Foundation

/// The lock-screen widget's three switches. Read straight from
/// `UserDefaults`, like `Preferences` — there is no state to hold.
enum LockScreenSettings {
    static var isWidgetEnabled: Bool {
        UserDefaults.standard.object(forKey: Preferences.lockScreenWidgetKey) as? Bool ?? true
    }

    static var showsNowPlaying: Bool {
        UserDefaults.standard.object(forKey: Preferences.lockScreenNowPlayingKey) as? Bool ?? true
    }

    static var showsClock: Bool {
        UserDefaults.standard.object(forKey: Preferences.lockScreenClockKey) as? Bool ?? true
    }
}
