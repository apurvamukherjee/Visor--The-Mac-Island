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
    /// What this design argues *should* be on. Advice, not a default: the
    /// switch still ships off, and the badge is the only difference.
    let isRecommended: Bool

    var id: String {
        key
    }

    func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

enum NewFeatures {
    /// The island already waits 120ms before it opens and nothing at all
    /// before it closes, which makes it deliberate on the way in and twitchy
    /// on the way out.
    static let closeIntentDelay = NewFeature(
        key: "newFeature.closeIntentDelay",
        title: "Wait before closing",
        detail: "Clipping the island's edge on the way to a button no longer slams it shut.",
        isRecommended: true
    )

    static let visibleDropZones = NewFeature(
        key: "newFeature.visibleDropZones",
        title: "Show drop zones",
        detail: "Drag a file over the island and it splits into Stash and AirDrop. "
            + "Holding ⌥ still sends, so the shortcut keeps working.",
        isRecommended: true
    )

    /// Swipe down currently only restores a dismissed activity, so on an
    /// island with nothing dismissed it does nothing at all.
    static let swipeDownOpens = NewFeature(
        key: "newFeature.swipeDownOpens",
        title: "Swipe down to open",
        detail: "A two-finger swipe down opens the island as well as bringing back "
            + "whatever you swiped away.",
        isRecommended: true
    )

    static let all: [NewFeature] = [closeIntentDelay, visibleDropZones, swipeDownOpens]

    static var keys: [String] {
        all.map(\.key)
    }
}
