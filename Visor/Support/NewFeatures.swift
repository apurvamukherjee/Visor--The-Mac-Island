import Foundation

/// One opt-in change to how the island behaves.
///
/// The feature program's governing rule is that nothing changes by default:
/// with every one of these off, Visor looks and acts exactly as it did
/// before. Declaring them in a single list is what makes that structural
/// rather than remembered — the settings row, the `UserDefaults` key and
/// the "Restore original settings" entry all read from here, so a toggle
/// cannot be added and then forgotten in one of the three.
///
/// The default is not stored anywhere, which is the point: the value is read
/// with `bool(forKey:)`, and a key nobody has written is `false`. "Off means
/// today's behaviour" is therefore a property of the type, not a convention
/// each new feature has to observe.
struct NewFeature: Identifiable, Sendable {
    let key: String
    let title: String
    /// One line under the toggle saying what turning it on actually does.
    let detail: String

    var id: String {
        key
    }

    func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

enum NewFeatures {
    /// Empty until the first opt-in change lands. The tab says so rather
    /// than showing an empty box.
    static let all: [NewFeature] = []

    static var keys: [String] {
        all.map(\.key)
    }
}
