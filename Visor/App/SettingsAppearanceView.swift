import SwiftUI

/// Where the island lives and what it looks like: the display it picks, the
/// outline, and the two trims that fit the drawn shape to the real cutout.
struct SettingsAppearanceView: View {
    var store: NotchStore

    @AppStorage(Preferences.screenChoiceKey) private var screenChoice = NotchScreenChoice.automatic.rawValue
    @AppStorage(Preferences.hidesInFullscreenKey) private var hidesInFullscreen = false
    @AppStorage(Preferences.strokeEnabledKey) private var strokeEnabled = false
    @AppStorage(Preferences.strokeWidthKey) private var strokeWidth = 1.0
    @AppStorage(Preferences.strokeOpacityKey) private var strokeOpacity = 0.25
    @AppStorage(Preferences.notchWidthOffsetKey) private var notchWidthOffset = 0.0
    @AppStorage(Preferences.notchHeightOffsetKey) private var notchHeightOffset = 0.0

    var body: some View {
        Form {
            Section("Placement") {
                Picker("Display", selection: $screenChoice) {
                    ForEach(NotchScreenChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }

                Toggle("Hide in full screen", isOn: $hidesInFullscreen)
            }

            Section("Outline") {
                Toggle("Draw an outline", isOn: $strokeEnabled)

                if strokeEnabled {
                    LabeledSlider(
                        "Width",
                        value: $strokeWidth,
                        range: 0.5 ... 4,
                        format: { String(format: "%.1f pt", $0) }
                    )
                    LabeledSlider(
                        "Opacity",
                        value: $strokeOpacity,
                        range: 0 ... 1,
                        format: { "\(Int($0 * 100))%" }
                    )
                }
            }

            Section {
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
            } header: {
                Text("Size")
            } footer: {
                Text("The island shows itself at the new size while you drag, so the trim can "
                    + "be dialled in against the real cutout rather than guessed at.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
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
}
