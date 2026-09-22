import SwiftUI

/// The third settings tab: one key per palette command.
///
/// Nothing is bound out of the box, and it does not need to be — the rows
/// are numbered 1-4 in the palette whether or not anything is configured
/// here. This tab is for the handful of commands somebody reaches for often
/// enough to want a letter.
struct ShortcutsView: View {
    @State private var shortcuts = PaletteShortcuts.load()
    @AppStorage(NewFeatures.commandPalette.key) private var paletteEnabled = false

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

                ForEach(PaletteCommand.all) { command in
                    ShortcutRow(
                        command: command,
                        key: shortcuts.key(for: command.id),
                        onChange: { assign($0, to: command.id) }
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
