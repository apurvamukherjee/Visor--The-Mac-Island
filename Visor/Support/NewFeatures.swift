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

    /// A new surface rather than a change to an existing one, so it ships
    /// off for the reason §2.1 gives for all of them: an island that grows
    /// a panel unasked is the same violation as one that changes its hover
    /// behaviour. No recommendation badge — this one is a matter of taste,
    /// not a fix.
    static let commandPalette = NewFeature(
        key: "newFeature.commandPalette",
        title: "Command palette",
        detail: "⌃⌥K opens a searchable list of commands in the island. "
            + "Needs no permission — it uses a registered hotkey, not a keyboard monitor.",
        isRecommended: false
    )

    /// The code for this shipped months ago and was wired to nothing — the
    /// audit found `LyricsFetcher` with exactly one reference, its own
    /// declaration. Turning it on adds a button to the player, which is a
    /// change to a working card, so it is opt-in like everything else.
    static let lyrics = NewFeature(
        key: "newFeature.lyrics",
        title: "Lyrics panel",
        detail: "Adds a lyrics button to the player. Words are fetched from LRCLIB only while "
            + "the panel is open, so music playing with it shut never reaches the network.",
        isRecommended: false
    )

    /// A new surface again, so it ships off like the rest. Reads only files
    /// the agents already write on this machine — no network, no permission,
    /// and nothing at all is opened while the switch is off.
    static let aiUsageTracker = NewFeature(
        key: "newFeature.aiUsageTracker",
        title: "AI usage badge",
        detail: "Shows today's Claude Code and Codex token use beside the notch. "
            + "It steps aside while music is playing and comes back when the island opens.",
        isRecommended: false
    )

    /// Rebinds a gesture that already does something, so it is off by default
    /// for the plainest reading of §2.1 there is: with the switch off, a
    /// swipe down still restores a dismissed activity and nothing new exists.
    static let usagePanel = NewFeature(
        key: "newFeature.usagePanel",
        title: "Swipe down for agent usage",
        detail: "A two-finger swipe down on the island opens today's Claude Code and Codex "
            + "figures with the live context window; swipe up to go back. "
            + "Reads the same files as the badge — no network, no permission.",
        isRecommended: false
    )

    static let all: [NewFeature] = [
        closeIntentDelay,
        visibleDropZones,
        swipeDownOpens,
        commandPalette,
        lyrics,
        aiUsageTracker,
        usagePanel
    ]

    static var keys: [String] {
        all.map(\.key)
    }
}
