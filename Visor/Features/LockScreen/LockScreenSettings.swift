import Foundation

/// Settings for the lock-screen padlock.
///
/// The media panel that used to sit on the lock screen is gone, and with it
/// every key that only configured it — widget appearance, tint, brightness,
/// liquid-glass variant, panel background, lyrics, expanded artwork and the
/// panel's vertical offset. The sound keys went the same way: nothing in
/// Visor has ever played a lock or unlock sound, so four defaults and their
/// migration were configuring silence. What remains is the padlock.
enum LockScreenSettings {
    static let liveActivityKey = "isLockScreenLiveActivityEnabled"
    static let styleKey = "settings.lockScreen.style"

    static func isLiveActivityEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: liveActivityKey, defaultValue: true, in: defaults)
    }

    static func style(in defaults: UserDefaults = .standard) -> LockScreenStyle {
        guard
            let rawValue = defaults.string(forKey: styleKey),
            let style = LockScreenStyle(rawValue: rawValue)
        else {
            return .compact
        }

        return style
    }

    private static func resolvedBoolean(
        forKey key: String,
        defaultValue: Bool,
        in defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return defaults.bool(forKey: key)
    }
}
