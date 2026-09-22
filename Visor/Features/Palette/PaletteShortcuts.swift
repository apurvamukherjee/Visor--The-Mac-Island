import Foundation

/// One key per command, pressed on its own once the palette is open.
///
/// **They fire only while the query is empty.** That is the whole rule, and
/// it is what lets a single key and a search box share one text field: bind
/// `d` to Dark Mode and the palette can still find "downloads", because by
/// the time you have typed `d`-`o` the query is no longer empty and every
/// key after the first types. The row badges are shown exactly when the keys
/// are live, so the state is never a guess.
///
/// Digits are deliberately not assignable: 1-9 always run the *visible* rows
/// in order, which costs no configuration and can never collide with a
/// search, since no command title begins with a digit.
struct PaletteShortcuts: Equatable, Sendable {
    private(set) var keys: [PaletteCommandID: Character]

    static let empty = PaletteShortcuts(keys: [:])

    init(keys: [PaletteCommandID: Character] = [:]) {
        self.keys = keys
    }

    func command(for character: Character) -> PaletteCommandID? {
        keys.first { $0.value == character }?.key
    }

    func key(for id: PaletteCommandID) -> Character? {
        keys[id]
    }

    /// Assigning steals. One key means one command, so binding a key that is
    /// already taken clears it from the command that had it rather than
    /// leaving two rows claiming the same press.
    func assigning(_ character: Character?, to id: PaletteCommandID) -> PaletteShortcuts {
        var updated = keys
        updated[id] = nil
        guard let character else { return PaletteShortcuts(keys: updated) }
        for (existing, key) in updated where key == character {
            updated[existing] = nil
        }
        updated[id] = character
        return PaletteShortcuts(keys: updated)
    }

    /// A single lowercased letter. Digits are rejected — they are reserved
    /// for the row numbers — and so is anything longer than one character,
    /// which is what a paste into the field produces.
    static func normalise(_ raw: String) -> Character? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 1, let character = trimmed.first else { return nil }
        guard character.isLetter else { return nil }
        return character
    }

    // MARK: - Storage

    static func load(from defaults: UserDefaults = .standard) -> PaletteShortcuts {
        guard let raw = defaults.dictionary(forKey: Preferences.paletteShortcutsKey) as? [String: String] else {
            return .empty
        }
        var keys: [PaletteCommandID: Character] = [:]
        for (rawID, rawKey) in raw {
            guard let id = PaletteCommandID(rawValue: rawID), let key = normalise(rawKey) else { continue }
            keys[id] = key
        }
        return PaletteShortcuts(keys: keys)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard !keys.isEmpty else {
            defaults.removeObject(forKey: Preferences.paletteShortcutsKey)
            return
        }
        let raw = keys.reduce(into: [String: String]()) { result, entry in
            result[entry.key.rawValue] = String(entry.value)
        }
        defaults.set(raw, forKey: Preferences.paletteShortcutsKey)
    }
}
