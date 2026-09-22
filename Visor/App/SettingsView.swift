import SwiftUI

/// The app's only window. Static by design — the power rules forbid anything
/// that animates or ticks, and nothing here does: the toggle reads its state
/// once when the window opens.
struct SettingsView: View {
    var store: NotchStore

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginFailed = false
    @State private var isConfirmingRestore = false
    /// `@AppStorage`, not `@State`: the island reads the same key and has to
    /// pick the change up while this window is still open.
    @AppStorage(Preferences.vinylModeKey) private var vinylMode = false
    /// Drives every spring in `Motion`. Stored as the raw value so
    /// `@AppStorage` can hold it; `Motion` reads the same key.
    @AppStorage(Preferences.motionPresetKey) private var motionPreset = MotionPreset.balanced.rawValue
    @AppStorage(Preferences.progressTintKey) private var progressTint = ProgressTintStyle.standard.rawValue
    @AppStorage(Preferences.equalizerKey) private var showEqualizer = false
    @AppStorage(LockScreenSettings.liveActivityKey) private var lockLiveActivity = true
    @AppStorage(LockScreenSettings.styleKey) private var lockStyle = LockScreenStyle.compact.rawValue
    @AppStorage(Preferences.strokeEnabledKey) private var strokeEnabled = false
    @AppStorage(Preferences.strokeWidthKey) private var strokeWidth = 1.0
    @AppStorage(Preferences.strokeOpacityKey) private var strokeOpacity = 0.25
    @AppStorage(Preferences.notchWidthOffsetKey) private var notchWidthOffset = 0.0
    @AppStorage(Preferences.notchHeightOffsetKey) private var notchHeightOffset = 0.0
    @AppStorage(Preferences.hidesInFullscreenKey) private var hidesInFullscreen = false
    @AppStorage(Preferences.screenChoiceKey) private var screenChoice = NotchScreenChoice.automatic.rawValue

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
        // Two tabs since the feature program started adding opt-in changes.
        // They stay out of the column below: that one is settings between
        // shipped options, this is a list of things that change how the app
        // already works, and the two read differently.
        TabView {
            // Scrollable since the notch and lock-screen sections landed: the
            // window is fixed-width by design, and a taller one would run off
            // a 13" screen.
            ScrollView {
                content
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }

            NewFeaturesView()
                .tabItem { Label("New Features", systemImage: "sparkles") }
        }
        .frame(width: 340, height: 560)
    }

    private var content: some View {
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

            SettingsSection("General") {
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
                        .multilineTextAlignment(.center)
                }
            }

            Divider()

            SettingsSection("Now Playing") {
                Toggle("Vinyl mode", isOn: $vinylMode)

                Text("Show a turning record instead of the album cover.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Progress colour", selection: $progressTint) {
                    ForEach(ProgressTintStyle.allCases, id: \.rawValue) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }

                Toggle("Show equaliser", isOn: $showEqualizer)

                Text("Decorative — macOS gives no app the system's audio levels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            SettingsSection("Lock Screen") {
                Toggle("Padlock in the notch", isOn: $lockLiveActivity)

                Picker("Padlock style", selection: $lockStyle) {
                    ForEach(LockScreenStyle.allCases, id: \.rawValue) { style in
                        Text(style == .compact ? "Icon only" : "Icon and label").tag(style.rawValue)
                    }
                }
                .disabled(!lockLiveActivity)
            }

            Divider()

            SettingsSection("Notch") {
                Picker("Display", selection: $screenChoice) {
                    ForEach(NotchScreenChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }

                Toggle("Hide in full screen", isOn: $hidesInFullscreen)

                Toggle("Outline", isOn: $strokeEnabled)

                if strokeEnabled {
                    LabeledSlider(
                        "Outline width",
                        value: $strokeWidth,
                        range: 0.5 ... 4,
                        format: { String(format: "%.1f pt", $0) }
                    )
                    LabeledSlider(
                        "Outline opacity",
                        value: $strokeOpacity,
                        range: 0 ... 1,
                        format: { "\(Int($0 * 100))%" }
                    )
                }

                LabeledSlider(
                    "Width trim",
                    value: $notchWidthOffset,
                    range: Preferences.notchWidthOffsetRange,
                    format: { String(format: "%+.0f pt", $0) }
                )
                .onChange(of: notchWidthOffset) { showSizeFeedback() }

                LabeledSlider(
                    "Height trim",
                    value: $notchHeightOffset,
                    range: Preferences.notchHeightOffsetRange,
                    format: { String(format: "%+.0f pt", $0) }
                )
                .onChange(of: notchHeightOffset) { showSizeFeedback() }
            }

            Divider()

            VStack(spacing: 10) {
                ShortcutRow(symbol: "cursorarrow.rays", label: "Hover the notch to expand it")
                ShortcutRow(symbol: "hand.tap.fill", label: "Double-click to play or pause")
                ShortcutRow(symbol: "hand.draw.fill", label: "Two-finger swipe sideways to change track")
                ShortcutRow(symbol: "chevron.up", label: "Swipe up to dismiss, down to bring it back")
                ShortcutRow(symbol: "airplayaudio", label: "Hold Option while dropping to AirDrop instead")
                ShortcutRow(symbol: "square.and.arrow.down.fill", label: "Drag a file onto the island to catch it")
                ShortcutRow(symbol: "gearshape.fill", label: "Right-click the island to open this window")
            }

            Divider()

            SettingsSection("About") {
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
                    Button("Restore", role: .destructive, action: restoreDefaults)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every setting here goes back to how it shipped. "
                        + "Launch at login is left alone.")
                }
            }

            Button("Quit Visor") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(24)
    }

    /// The island redraws itself at the new trim while the slider moves, so
    /// the numbers can be dialled in by eye rather than guessed at and then
    /// checked. Not a new mechanism — it is the ordinary compact peek, the
    /// same one a charger or a screenshot triggers.
    private func showSizeFeedback() {
        store.notchWidthOffset = notchWidthOffset
        store.notchHeightOffset = notchHeightOffset
        store.previewNotchSize()
    }

    /// Clears the stored keys, then pulls this window's `@AppStorage` values
    /// back to the defaults by hand. `removeObject` does not notify the
    /// property wrappers — they would keep showing the cleared values until
    /// the window was reopened — and `Motion.preset` and the store's trim are
    /// caches of those same keys, so both are refreshed here too.
    private func restoreDefaults() {
        Preferences.restoreDefaults()

        vinylMode = false
        motionPreset = MotionPreset.balanced.rawValue
        progressTint = ProgressTintStyle.standard.rawValue
        showEqualizer = false
        lockLiveActivity = true
        lockStyle = LockScreenStyle.compact.rawValue
        strokeEnabled = false
        strokeWidth = 1
        strokeOpacity = 0.25
        notchWidthOffset = 0
        notchHeightOffset = 0
        hidesInFullscreen = false
        screenChoice = NotchScreenChoice.automatic.rawValue

        Motion.preset = .balanced
        showSizeFeedback()
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

/// A slider with its label and current value above it — `Slider`'s own
/// label sits beside the track and squeezes it to nothing at this width.
private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            Slider(value: $value, in: range)
        }
    }
}

/// A labelled group of rows. Purely visual — every row still owns its own
/// state — introduced once the flat list grew past a glance's worth of
/// unrelated toggles.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of the shortcut sheet: a System Settings–style tinted icon tile
/// plus a label, in place of the sentence-per-gesture prose this replaced.
private struct ShortcutRow: View {
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
