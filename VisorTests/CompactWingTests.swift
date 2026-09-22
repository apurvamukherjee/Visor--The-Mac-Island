import Foundation
import Testing
@testable import Visor

/// The bug this pins: the compact wing was a flat 160pt — 64 of it usable —
/// while the greeting it had to carry wanted 130, so most of "Good
/// afternoon, Apurva" was drawn underneath the camera housing, where there
/// is no screen. Measured on the real font, 2026-09-23.
@Suite("Compact wing")
struct CompactWingTests {
    /// What `CompactActivityView` leaves for the label after its own padding.
    private func usableWing(_ layout: IslandLayout) -> CGFloat {
        layout.compactExtraWidth / 2 - (NotchRadii.compact.bottom + 2)
    }

    @Test("The wing fits the label it was sized for")
    func wingFitsItsLabel() {
        for message in [
            "Still up, Apurva",
            "Good afternoon, Apurva",
            "Good morning, Alexandra"
        ] {
            let width = CompactLabel.width(message)
            let layout = IslandLayout.idle(IslandContent(compactLeadingWidth: width))
            #expect(usableWing(layout) >= width, "\(message) still overflows the wing")
        }
    }

    /// Nothing else may pay for the greeting's width.
    @Test("An island with no long label keeps the width it always had")
    func noLabelKeepsTheOldWing() {
        #expect(IslandLayout.idle(IslandContent()).compactExtraWidth == 160)
        #expect(IslandLayout.idle(IslandContent(agendaRows: 3)).compactExtraWidth == 160)
    }

    @Test("A label measures its glyph and gap, and stops growing at the cap")
    func widthIncludesGlyphAndClamps() {
        #expect(CompactLabel.width("") == CompactLabel.glyphSize + CompactLabel.spacing)
        #expect(CompactLabel.width(String(repeating: "W", count: 200)) == CompactLabel.maxWidth)
        #expect(CompactLabel.width("Good afternoon, Apurva") > CompactLabel.width("Focus on"))
    }

    /// The canvas is sized from `IslandLayout.all`; a greeting wider than it
    /// would be clipped by the window rather than drawn.
    @Test("The widest greeting still fits the canvas")
    func widestGreetingFitsTheCanvas() {
        let widest = IslandLayout.idle(IslandContent(compactLeadingWidth: CompactLabel.maxWidth))
        #expect(widest.compactExtraWidth <= IslandLayout.maxCompactExtraWidth)
        #expect(widest.expandedExtraWidth <= IslandLayout.maxExpandedExtraWidth)
    }
}

@Suite("Greeting name")
struct GreetingNameTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    /// Unset means the account's own name, not a hardcoded one — the
    /// greeting said "Apurva" to everybody before this.
    @Test("Unset falls back to the account name")
    func unsetUsesTheAccountName() {
        #expect(Preferences.userName(in: makeDefaults()) == Preferences.defaultUserName)
        #expect(!Preferences.defaultUserName.isEmpty)
    }

    @Test("A set name is used, and whitespace is not a name")
    func storedNameWins() {
        let defaults = makeDefaults()
        defaults.set("Rohit", forKey: Preferences.userNameKey)
        #expect(Preferences.userName(in: defaults) == "Rohit")

        defaults.set("  Rohit  ", forKey: Preferences.userNameKey)
        #expect(Preferences.userName(in: defaults) == "Rohit")

        defaults.set("   ", forKey: Preferences.userNameKey)
        #expect(Preferences.userName(in: defaults) == Preferences.defaultUserName)
    }

    @Test("Restoring defaults clears the name")
    func restoreClearsTheName() {
        let defaults = makeDefaults()
        defaults.set("Rohit", forKey: Preferences.userNameKey)

        Preferences.restoreDefaults(in: defaults)

        #expect(Preferences.userName(in: defaults) == Preferences.defaultUserName)
    }
}
