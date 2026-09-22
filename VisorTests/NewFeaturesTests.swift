import Foundation
import Testing
@testable import Visor

/// Pins the governing rule of the feature program: with every opt-in change
/// off, Visor behaves as it did before. The list is empty until the first
/// one lands, so these are guard rails rather than assertions about today —
/// which is the point of writing them before the first row exists.
@Suite("New features")
struct NewFeaturesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    @Test("Every opt-in change is off until someone turns it on")
    func defaultsToTodaysBehaviour() {
        let defaults = makeDefaults()

        for feature in NewFeatures.all {
            #expect(feature.isEnabled(in: defaults) == false, "\(feature.key) ships on")
        }
    }

    @Test("Keys are unique")
    func keysAreUnique() {
        #expect(Set(NewFeatures.keys).count == NewFeatures.keys.count)
    }

    /// A key reused from the Settings tab would make one switch move two
    /// things — and "Restore original settings" would then reset a shipped
    /// preference by way of an opt-in change.
    @Test("No key collides with a shipped preference")
    func keysDoNotCollideWithSettings() {
        let shipped = Set(Preferences.resettableKeys).subtracting(NewFeatures.keys)

        for key in NewFeatures.keys {
            #expect(!shipped.contains(key), "\(key) is already a shipped preference")
        }
    }

    /// Restoring defaults has to reach them, or turning one on would outlive
    /// the button that claims to undo everything.
    @Test("Restoring defaults clears every opt-in change")
    func restoreClearsThem() {
        let defaults = makeDefaults()
        for key in NewFeatures.keys {
            defaults.set(true, forKey: key)
        }

        Preferences.restoreDefaults(in: defaults)

        for feature in NewFeatures.all {
            #expect(feature.isEnabled(in: defaults) == false, "\(feature.key) survived the restore")
        }
    }
}
