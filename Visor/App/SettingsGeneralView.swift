import AppKit
import SwiftUI

/// Who you are, how fast the island moves, and the three buttons an
/// accessory app has nowhere else to put — with no menu bar, About and Quit
/// have to live in the settings window or nowhere.
struct SettingsGeneralView: View {
    var store: NotchStore
    let onRestore: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginFailed = false
    @State private var isConfirmingRestore = false

    @AppStorage(Preferences.userNameKey) private var userName = ""
    /// Drives every spring in `Motion`. Stored as the raw value so
    /// `@AppStorage` can hold it; `Motion` reads the same key.
    @AppStorage(Preferences.motionPresetKey) private var motionPreset = MotionPreset.balanced.rawValue

    private var launchAtLoginHint: String {
        LaunchAtLogin.isInstalled
            ? "macOS refused the login-item change. Check Login Items in System Settings."
            : "Move Visor to your Applications folder first — macOS won't register a login item "
            + "for an app running from a build folder or a disk image."
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $userName, prompt: Text(Preferences.defaultUserName))

                Picker("Animation speed", selection: $motionPreset) {
                    ForEach(MotionPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                .onChange(of: motionPreset) { _, raw in
                    Motion.preset = MotionPreset(rawValue: raw) ?? .balanced
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(to: enabled)
                    }

                if launchAtLoginFailed {
                    Text(launchAtLoginHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("The name is what the daily greeting calls you. Left empty it uses your "
                    + "account name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Replay welcome tour") {
                    store.onboardingCommands?.replay()
                }

                Button("Restore original settings") {
                    isConfirmingRestore = true
                }
                .confirmationDialog(
                    "Restore original settings?",
                    isPresented: $isConfirmingRestore,
                    titleVisibility: .visible
                ) {
                    Button("Restore", role: .destructive, action: onRestore)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every setting here goes back to how it shipped. "
                        + "Launch at login is left alone.")
                }

                Button("Quit Visor") {
                    NSApplication.shared.terminate(nil)
                }
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("By", value: "Apurva")
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(to enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginFailed = false
        } catch {
            Log.app.error("Launch at login failed: \(error.localizedDescription)")
            launchAtLoginFailed = true
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
