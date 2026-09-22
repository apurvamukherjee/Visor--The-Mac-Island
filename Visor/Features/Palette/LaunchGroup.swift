import Foundation

/// One app in a launch group. The bundle identifier is what is stored and
/// resolved at launch time — a path would break the moment the app moved
/// inside `/Applications`. `displayName` is cached at add-time purely so the
/// Shortcuts tab can list a group's apps without resolving anything.
struct LaunchGroupApp: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
}

/// A user-named set of apps opened together. Entirely user-authored —
/// nothing here is a preloaded preset.
struct LaunchGroup: Codable, Equatable, Sendable {
    var name: String = ""
    var apps: [LaunchGroupApp] = []

    static let empty = LaunchGroup()

    /// A named group with no apps, or an unnamed pile of apps, are both
    /// still nothing the palette should offer — see
    /// `PaletteCommand.Availability.whileGroupConfigured`.
    var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !apps.isEmpty
    }
}

/// One `LaunchGroup` per launch-group slot, persisted as a single JSON blob
/// keyed by `PaletteCommandID.rawValue` — the same one-key-per-write shape
/// `PaletteShortcuts` uses for the same reason: a command that no longer
/// exists, or a slot nobody has touched, must not take the rest down with it.
struct LaunchGroups: Equatable, Sendable {
    private(set) var groups: [PaletteCommandID: LaunchGroup]

    static let empty = LaunchGroups(groups: [:])

    init(groups: [PaletteCommandID: LaunchGroup] = [:]) {
        self.groups = groups
    }

    func group(for id: PaletteCommandID) -> LaunchGroup {
        groups[id] ?? .empty
    }

    var configuredIDs: Set<PaletteCommandID> {
        Set(groups.filter(\.value.isConfigured).keys)
    }

    func updating(_ group: LaunchGroup, for id: PaletteCommandID) -> LaunchGroups {
        var updated = groups
        updated[id] = group
        return LaunchGroups(groups: updated)
    }

    // MARK: - Storage

    static func load(from defaults: UserDefaults = .standard) -> LaunchGroups {
        guard
            let data = defaults.data(forKey: Preferences.launchGroupsKey),
            let raw = try? JSONDecoder().decode([String: LaunchGroup].self, from: data)
        else {
            return .empty
        }
        var groups: [PaletteCommandID: LaunchGroup] = [:]
        for (rawID, group) in raw {
            guard let id = PaletteCommandID(rawValue: rawID) else { continue }
            groups[id] = group
        }
        return LaunchGroups(groups: groups)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard !groups.isEmpty else {
            defaults.removeObject(forKey: Preferences.launchGroupsKey)
            return
        }
        let raw = groups.reduce(into: [String: LaunchGroup]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: Preferences.launchGroupsKey)
    }
}
