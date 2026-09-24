import SwiftUI

/// The player card, and the padlock that replaces it while the screen is
/// locked. Both are what the island draws when music is what is happening, so
/// they share a pane rather than a column apiece.
struct SettingsNowPlayingView: View {
    @AppStorage(Preferences.vinylModeKey) private var vinylMode = false
    @AppStorage(Preferences.progressTintKey) private var progressTint = ProgressTintStyle.standard.rawValue
    @AppStorage(Preferences.equalizerKey) private var showEqualizer = false
    @AppStorage(LockScreenSettings.liveActivityKey) private var lockLiveActivity = true
    @AppStorage(LockScreenSettings.styleKey) private var lockStyle = LockScreenStyle.compact.rawValue

    var body: some View {
        Form {
            Section {
                Toggle("Vinyl mode", isOn: $vinylMode)

                Picker("Progress colour", selection: $progressTint) {
                    ForEach(ProgressTintStyle.allCases, id: \.rawValue) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }

                Toggle("Show equaliser", isOn: $showEqualizer)
            } header: {
                Text("Player")
            } footer: {
                Text("Vinyl mode turns a record instead of showing the album cover. The "
                    + "equaliser moves to the card's right edge instead of sitting on the "
                    + "cover; it is decorative either way — macOS gives no app the system's "
                    + "audio levels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Lock Screen") {
                Toggle("Padlock in the notch", isOn: $lockLiveActivity)

                Picker("Padlock style", selection: $lockStyle) {
                    ForEach(LockScreenStyle.allCases, id: \.rawValue) { style in
                        Text(style == .compact ? "Icon only" : "Icon and label").tag(style.rawValue)
                    }
                }
                .disabled(!lockLiveActivity)
            }
        }
        .formStyle(.grouped)
    }
}
