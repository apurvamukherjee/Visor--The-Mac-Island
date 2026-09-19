import Foundation

/// Settings for the lock-screen padlock.
///
/// The media panel that used to sit on the lock screen is gone, and with it
/// every key that only configured it — widget appearance, tint, brightness,
/// liquid-glass variant, panel background, lyrics, expanded artwork and the
/// panel's vertical offset. What remains is the padlock and its sounds.
enum LockScreenSettings {
    static let liveActivityKey = "isLockScreenLiveActivityEnabled"
    static let soundKey = "isLockScreenSoundEnabled"
    static let customSoundPathKey = "settings.lockScreen.customSoundPath"
    static let customLockSoundPathKey = "settings.lockScreen.customLockSoundPath"
    static let customUnlockSoundPathKey = "settings.lockScreen.customUnlockSoundPath"
    static let styleKey = "settings.lockScreen.style"

    static func isLiveActivityEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: liveActivityKey, defaultValue: true, in: defaults)
    }

    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: soundKey, defaultValue: true, in: defaults)
    }

    static func legacyCustomSoundPath(in defaults: UserDefaults = .standard) -> String? {
        resolvedPath(forKey: customSoundPathKey, in: defaults)
    }

    static func customLockSoundPath(in defaults: UserDefaults = .standard) -> String? {
        resolvedPath(forKey: customLockSoundPathKey, in: defaults)
    }

    static func customUnlockSoundPath(in defaults: UserDefaults = .standard) -> String? {
        resolvedPath(forKey: customUnlockSoundPathKey, in: defaults)
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

    private static func resolvedPath(forKey key: String, in defaults: UserDefaults) -> String? {
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}
