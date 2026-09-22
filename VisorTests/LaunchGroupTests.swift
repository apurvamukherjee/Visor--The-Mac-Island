import Foundation
import Testing
@testable import Visor

/// A group with no name, or a name with no apps, must read as unconfigured —
/// otherwise the palette would offer a row that launches nothing.
@Suite("Launch group")
struct LaunchGroupTests {
    @Test("Configured needs both a name and at least one app")
    func configuredNeedsBoth() {
        #expect(!LaunchGroup.empty.isConfigured)
        #expect(!LaunchGroup(name: "Office").isConfigured)
        #expect(!LaunchGroup(apps: [LaunchGroupApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari")])
            .isConfigured)
        #expect(LaunchGroup(
            name: "Office",
            apps: [LaunchGroupApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari")]
        ).isConfigured)
        // Whitespace-only is the same as empty.
        #expect(!LaunchGroup(
            name: "   ",
            apps: [LaunchGroupApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari")]
        ).isConfigured)
    }
}

@Suite("Launch groups storage")
struct LaunchGroupsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    @Test("Groups survive a round trip through defaults")
    func storageRoundTrip() {
        let defaults = freshDefaults()
        let office = LaunchGroup(
            name: "Office",
            apps: [
                LaunchGroupApp(bundleIdentifier: "net.openvpn.connect", displayName: "OpenVPN Connect"),
                LaunchGroupApp(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            ]
        )
        let groups = LaunchGroups().updating(office, for: .launchGroup1)
        groups.save(to: defaults)

        #expect(LaunchGroups.load(from: defaults) == groups)

        LaunchGroups.empty.save(to: defaults)
        #expect(LaunchGroups.load(from: defaults) == .empty)
    }

    @Test("An unknown slot in the plist is dropped, not fatal")
    func storageIgnoresJunk() {
        let defaults = freshDefaults()
        let raw: [String: LaunchGroup] = [
            "launchGroup1": LaunchGroup(name: "Office", apps: [
                LaunchGroupApp(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            ]),
            "somethingRemoved": LaunchGroup(name: "Ghost", apps: [])
        ]
        defaults.set(try? JSONEncoder().encode(raw), forKey: Preferences.launchGroupsKey)

        let loaded = LaunchGroups.load(from: defaults)
        #expect(loaded.groups.count == 1)
        #expect(loaded.group(for: .launchGroup1).name == "Office")
    }

    @Test("configuredIDs holds only slots with a name and an app")
    func configuredIDsFiltersEmptySlots() {
        let groups = LaunchGroups()
            .updating(LaunchGroup(name: "Office", apps: [
                LaunchGroupApp(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
            ]), for: .launchGroup1)
            .updating(LaunchGroup(name: "Half-set"), for: .launchGroup2)

        #expect(groups.configuredIDs == [.launchGroup1])
    }
}

/// The launch itself cannot be exercised without installing or removing a
/// real app, but the resolve-or-skip branch can, via the injected lookup.
@MainActor
@Suite("System commands launch")
struct SystemCommandsLaunchTests {
    @Test("A bundle ID that no longer resolves is skipped, not fatal")
    func missingAppIsSkipped() {
        let commands = SystemCommands()
        let group = LaunchGroup(name: "Office", apps: [
            LaunchGroupApp(bundleIdentifier: "com.example.missing", displayName: "Missing"),
            LaunchGroupApp(bundleIdentifier: "com.example.present", displayName: "Present")
        ])
        var resolved: [String] = []

        commands.launch(group) { identifier in
            resolved.append(identifier)
            return identifier == "com.example.present" ? URL(fileURLWithPath: "/Applications/Present.app") : nil
        }

        #expect(resolved == ["com.example.missing", "com.example.present"])
    }
}
