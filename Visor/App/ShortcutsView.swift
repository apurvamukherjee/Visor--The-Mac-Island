import AppKit
import SwiftUI

/// The third settings tab: one key per palette command, plus the ten launch
/// groups' own name and app list.
///
/// Nothing is bound out of the box, and it does not need to be — the rows
/// are numbered 1-4 in the palette whether or not anything is configured
/// here. This tab is for the handful of commands somebody reaches for often
/// enough to want a letter.
struct ShortcutsView: View {
    @State private var shortcuts = PaletteShortcuts.load()
    @State private var launchGroups = LaunchGroups.load()
    @AppStorage(NewFeatures.commandPalette.key) private var paletteEnabled = false

    private static let ordinaryCommands = PaletteCommand.all.filter {
        !Self.launchGroupIDs.contains($0.id)
    }

    private static let launchGroupIDs: [PaletteCommandID] = [
        .launchGroup1, .launchGroup2, .launchGroup3, .launchGroup4, .launchGroup5,
        .launchGroup6, .launchGroup7, .launchGroup8, .launchGroup9, .launchGroup10
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Open the palette with ⌃⌥K, then press a key to run a command. "
                    + "Keys work only before you start typing — after the first letter "
                    + "everything searches, so a key here never costs you a search.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !paletteEnabled {
                    Text("The command palette is off. Turn it on in New Features.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("1 – 4 always run the visible rows in order, whatever is set below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("GESTURES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    GestureRow(symbol: "cursorarrow.rays", label: "Hover the notch to expand it")
                    GestureRow(symbol: "hand.tap.fill", label: "Double-click to play or pause")
                    GestureRow(symbol: "hand.draw.fill", label: "Two-finger swipe sideways to change track")
                    GestureRow(symbol: "chevron.up.chevron.down", label: "Swipe up and down to turn between screens")
                    GestureRow(symbol: "airplayaudio", label: "Hold Option while dropping to AirDrop instead")
                    GestureRow(symbol: "square.and.arrow.down.fill", label: "Drag a file onto the island to catch it")
                    GestureRow(symbol: "gearshape.fill", label: "Right-click the island to open this window")
                }

                Divider()

                Divider()

                ForEach(Self.ordinaryCommands) { command in
                    ShortcutRow(
                        command: command,
                        key: shortcuts.key(for: command.id),
                        onChange: { assign($0, to: command.id) }
                    )
                }

                Divider()

                Text("Launch Groups")
                    .font(.headline)
                Text("Name a group and add the apps it should open together — nothing is "
                    + "preloaded. An empty group never appears in the palette.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Self.launchGroupIDs, id: \.self) { id in
                    LaunchGroupRow(
                        group: launchGroups.group(for: id),
                        key: shortcuts.key(for: id),
                        onGroupChange: { updateGroup($0, for: id) },
                        onKeyChange: { assign($0, to: id) }
                    )
                }

                Divider()

                Button("Clear all keys") {
                    shortcuts = .empty
                    shortcuts.save()
                }
                .disabled(shortcuts.keys.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    /// Assigning steals the key from whatever had it, so the list can never
    /// show the same letter twice.
    private func assign(_ raw: String, to id: PaletteCommandID) {
        shortcuts = shortcuts.assigning(PaletteShortcuts.normalise(raw), to: id)
        shortcuts.save()
    }

    private func updateGroup(_ group: LaunchGroup, for id: PaletteCommandID) {
        launchGroups = launchGroups.updating(group, for: id)
        launchGroups.save()
    }
}

private struct ShortcutRow: View {
    let command: PaletteCommand
    let key: Character?
    let onChange: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(command.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 44)
                .onChange(of: text) { _, new in
                    // Keep only the last character typed, so replacing a key
                    // is one keystroke rather than select-all-then-type.
                    let trimmed = new.isEmpty ? "" : String(new.suffix(1))
                    if trimmed != new {
                        text = trimmed
                    }
                    onChange(trimmed)
                }
        }
        .onAppear { text = key.map(String.init) ?? "" }
        .onChange(of: key) { _, new in
            // Another row stealing this key clears the field here.
            let resolved = new.map(String.init) ?? ""
            if resolved != text {
                text = resolved
            }
        }
    }
}

/// One launch-group slot: a disclosure so ten mostly-empty groups do not
/// turn the tab into a wall of controls before anyone has named one.
private struct LaunchGroupRow: View {
    let group: LaunchGroup
    let key: Character?
    let onGroupChange: (LaunchGroup) -> Void
    let onKeyChange: (String) -> Void

    @State private var isExpanded = false
    @State private var name: String = ""
    @State private var keyText: String = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name, e.g. Office", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, new in
                        var updated = group
                        updated.name = new
                        onGroupChange(updated)
                    }

                ForEach(group.apps, id: \.bundleIdentifier) { app in
                    HStack(spacing: 8) {
                        Text(app.displayName)
                            .font(.callout)
                        Spacer()
                        Button {
                            removeApp(app)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Button("Add App…", action: addApp)
                    Spacer()
                    Text("Key")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("", text: $keyText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .onChange(of: keyText) { _, new in
                            let trimmed = new.isEmpty ? "" : String(new.suffix(1))
                            if trimmed != new {
                                keyText = trimmed
                            }
                            onKeyChange(trimmed)
                        }
                }
            }
            .padding(.top, 6)
            .padding(.leading, 26)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(group.name.isEmpty ? "Unconfigured" : group.name)
                    .font(.callout)
                    .lineLimit(1)
            }
        }
        .onAppear {
            name = group.name
            keyText = key.map(String.init) ?? ""
        }
        .onChange(of: key) { _, new in
            let resolved = new.map(String.init) ?? ""
            if resolved != keyText {
                keyText = resolved
            }
        }
    }

    private func removeApp(_ app: LaunchGroupApp) {
        var updated = group
        updated.apps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        onGroupChange(updated)
    }

    /// Bundle identifier, not path: an app that moves inside `/Applications`
    /// still resolves at launch time. `displayName` is cached here so the
    /// list above never has to re-resolve anything just to draw itself.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var updated = group
        for url in panel.urls {
            guard let identifier = Bundle(url: url)?.bundleIdentifier else { continue }
            guard !updated.apps.contains(where: { $0.bundleIdentifier == identifier }) else { continue }
            let displayName = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            updated.apps.append(LaunchGroupApp(bundleIdentifier: identifier, displayName: displayName))
        }
        onGroupChange(updated)
    }
}

/// One row of the gesture sheet: a System Settings-style tinted icon tile
/// plus a label, in place of the sentence-per-gesture prose this replaced.
private struct GestureRow: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.secondary, in: RoundedRectangle(cornerRadius: 6))
            Text(label)
                .font(.footnote)
            Spacer(minLength: 0)
        }
    }
}
