import Foundation
import Testing
@testable import Visor

/// A key that runs the wrong command is worse than no key at all, and the
/// rule that makes single keys and a search box coexist is subtle enough to
/// deserve pinning rather than remembering.
@Suite("Palette shortcuts")
struct PaletteShortcutTests {
    @Test("A key is one letter, lowercased")
    func normalisation() {
        #expect(PaletteShortcuts.normalise("D") == "d")
        #expect(PaletteShortcuts.normalise(" d ") == "d")
        #expect(PaletteShortcuts.normalise("") == nil)
        #expect(PaletteShortcuts.normalise("dd") == nil)
        // Digits belong to the row numbers and cannot be reassigned.
        #expect(PaletteShortcuts.normalise("3") == nil)
        #expect(PaletteShortcuts.normalise("-") == nil)
    }

    /// One key, one command — otherwise two rows claim the same press and
    /// which one wins is down to dictionary ordering.
    @Test("Assigning a taken key steals it")
    func assigningSteals() {
        let shortcuts = PaletteShortcuts()
            .assigning("d", to: .toggleDarkMode)
            .assigning("d", to: .openDownloads)

        #expect(shortcuts.key(for: .toggleDarkMode) == nil)
        #expect(shortcuts.key(for: .openDownloads) == "d")
        #expect(shortcuts.command(for: "d") == .openDownloads)
    }

    @Test("Assigning nil clears")
    func assigningNilClears() {
        let shortcuts = PaletteShortcuts()
            .assigning("d", to: .toggleDarkMode)
            .assigning(nil, to: .toggleDarkMode)

        #expect(shortcuts.keys.isEmpty)
        #expect(shortcuts.command(for: "d") == nil)
    }

    @Test("Keys survive a round trip through defaults")
    func storageRoundTrip() {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        let shortcuts = PaletteShortcuts()
            .assigning("d", to: .toggleDarkMode)
            .assigning("k", to: .keepAwake)
        shortcuts.save(to: defaults)

        #expect(PaletteShortcuts.load(from: defaults) == shortcuts)

        PaletteShortcuts.empty.save(to: defaults)
        #expect(PaletteShortcuts.load(from: defaults) == .empty)
    }

    /// Garbage in the plist — a hand-edited default, or a command that no
    /// longer exists — must not take the whole map down with it.
    @Test("Unknown commands and bad keys are dropped, not fatal")
    func storageIgnoresJunk() {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        defaults.set(
            ["toggleDarkMode": "d", "somethingRemoved": "x", "keepAwake": "not a key"],
            forKey: Preferences.paletteShortcutsKey
        )

        let loaded = PaletteShortcuts.load(from: defaults)
        #expect(loaded.keys.count == 1)
        #expect(loaded.key(for: .toggleDarkMode) == "d")
    }
}

/// The resolution rule: keys fire only while the query is empty.
@MainActor
@Suite("Palette shortcut resolution")
struct PaletteShortcutResolutionTests {
    private func openPalette(binding key: Character?, to id: PaletteCommandID) -> NotchStore {
        let store = NotchStore()
        store.openPalette()
        if let key {
            store.paletteShortcuts = PaletteShortcuts().assigning(key, to: id)
        }
        return store
    }

    /// The whole reason the rule exists: `d` runs Dark Mode from an empty
    /// query, but typing "do…" to find Downloads still works, because after
    /// the first letter nothing is a shortcut any more.
    @Test("Keys fire on an empty query and stop once typing starts")
    func keysOnlyFireBeforeTyping() {
        let store = openPalette(binding: "d", to: .toggleDarkMode)

        #expect(store.isPaletteShortcutModeActive)
        #expect(store.paletteCommand(forShortcut: "d") == .toggleDarkMode)

        store.updatePaletteQuery("d")
        #expect(!store.isPaletteShortcutModeActive)
        #expect(store.paletteCommand(forShortcut: "d") == nil)
    }

    @Test("Digits run the visible rows in order")
    func digitsRunVisibleRows() {
        let store = NotchStore()
        store.openPalette()
        let visible = store.visiblePaletteResults

        #expect(!visible.isEmpty)
        #expect(store.paletteCommand(forShortcut: "1") == visible.first?.id)
        let lastDigit = Character("\(visible.count)")
        #expect(store.paletteCommand(forShortcut: lastDigit) == visible.last?.id)
        // Past the visible rows there is nothing to run.
        #expect(store.paletteCommand(forShortcut: "9") == nil)
    }

    /// A key bound to something the palette has decided cannot act — a
    /// transport command with nothing playing — must not reach it.
    @Test("A key for an unavailable command does nothing")
    func unavailableCommandsAreUnreachable() {
        let store = openPalette(binding: "n", to: .nextTrack)

        #expect(!store.paletteResults.contains { $0.id == .nextTrack })
        #expect(store.paletteCommand(forShortcut: "n") == nil)
    }

    @Test("An unbound letter is typed, not swallowed")
    func unboundLettersType() {
        let store = openPalette(binding: "d", to: .toggleDarkMode)
        #expect(store.paletteCommand(forShortcut: "z") == nil)
    }

    /// The badges are drawn from the same flag the keys read, so the island
    /// can never show a key that would not work.
    @Test("Badges and keys agree")
    func badgesFollowTheKeys() {
        let store = NotchStore()
        store.openPalette()
        #expect(store.isPaletteShortcutModeActive)

        store.updatePaletteQuery("lock")
        #expect(!store.isPaletteShortcutModeActive)

        store.updatePaletteQuery("")
        #expect(store.isPaletteShortcutModeActive)
    }
}
