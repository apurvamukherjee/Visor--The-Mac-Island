import Foundation
import Testing
@testable import Visor

/// `restoreDefaults` works by *removing* keys, so the thing worth pinning is
/// that every accessor then reports its shipped default again — and that the
/// two keys which are not settings survive.
@Suite("Preferences restore")
struct PreferencesRestoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    @Test("Clears every resettable key")
    func clearsResettableKeys() {
        let defaults = makeDefaults()
        for key in Preferences.resettableKeys {
            defaults.set("dirty", forKey: key)
        }

        Preferences.restoreDefaults(in: defaults)

        for key in Preferences.resettableKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) survived the restore")
        }
    }

    @Test("Leaves onboarding and greeting state alone")
    func keepsNonSettings() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: Preferences.hasSeenWelcomeKey)
        defaults.set("2026-09-20", forKey: Preferences.lastGreetingDayKey)

        Preferences.restoreDefaults(in: defaults)

        #expect(defaults.bool(forKey: Preferences.hasSeenWelcomeKey))
        #expect(defaults.string(forKey: Preferences.lastGreetingDayKey) == "2026-09-20")
    }

    /// The restore button re-assigns `@AppStorage` by hand, so these are the
    /// values it must match. A default changed in one place and not the other
    /// is precisely the drift this catches.
    @Test("Lock-screen accessors report their shipped defaults after a restore")
    func lockScreenDefaults() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: LockScreenSettings.liveActivityKey)
        defaults.set(false, forKey: LockScreenSettings.soundKey)
        defaults.set(LockScreenStyle.enlarged.rawValue, forKey: LockScreenSettings.styleKey)

        Preferences.restoreDefaults(in: defaults)

        #expect(LockScreenSettings.isLiveActivityEnabled(in: defaults))
        #expect(LockScreenSettings.isSoundEnabled(in: defaults))
        #expect(LockScreenSettings.style(in: defaults) == .compact)
    }
}
