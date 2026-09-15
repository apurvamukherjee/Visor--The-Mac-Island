import SwiftUI

/// The app's only window. Static by design — the power rules forbid anything
/// that animates or ticks, and nothing here does: the toggle reads its state
/// once when the window opens.
struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginFailed = false
    /// `@AppStorage`, not `@State`: the island reads the same key and has to
    /// pick the change up while this window is still open.
    @AppStorage(Preferences.vinylModeKey) private var vinylMode = false

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
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Visor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("by Apurva")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLaunchAtLogin(to: enabled)
                }

            if launchAtLoginFailed {
                Text(launchAtLoginHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Toggle("Vinyl mode", isOn: $vinylMode)

            Text("Show a turning record instead of the album cover.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 6) {
                Text("Hover the notch to expand it.")
                Text("Two-finger swipe to change track. Double-click to play or pause.")
                Text("Right-click the notch to open this window.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button("Quit Visor") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(24)
        .frame(width: 340)
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
