import SwiftUI

/// The second settings tab: everything the feature program adds that changes
/// how the island already behaves, each one off until it is asked for.
///
/// Separate from the Settings tab on purpose. These are not preferences
/// between equally-shipped options — they are changes to a working app, and
/// mixing them into the existing column would bury that distinction under a
/// twelfth section.
struct NewFeaturesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nothing here is on until you turn it on. With every switch off, "
                    + "Visor behaves exactly as it always has.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if NewFeatures.all.isEmpty {
                    Text("Nothing to try yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(NewFeatures.all) { feature in
                        NewFeatureRow(feature: feature)
                    }

                    Divider()

                    HoverDelaySlider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

/// The one value in this tab rather than a switch: hover delay has a
/// number, not an off position, so it cannot ride `NewFeature`'s "unset
/// means today's behaviour" guarantee and carries its own default.
private struct HoverDelaySlider: View {
    @AppStorage(Preferences.hoverIntentDelayKey)
    private var milliseconds = Preferences.hoverIntentDelayDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Hover delay")
                Spacer()
                Text("\(Int(milliseconds)) ms")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            Slider(value: $milliseconds, in: Preferences.hoverIntentDelayRange)
            Text("How long the pointer rests on the island before it opens. 120 ms is the default.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One switch and the sentence that says what it does.
private struct NewFeatureRow: View {
    let feature: NewFeature

    /// Built from the feature's own key, so the list is the only place a key
    /// is written down.
    @AppStorage private var isOn: Bool

    init(feature: NewFeature) {
        self.feature = feature
        _isOn = AppStorage(wrappedValue: false, feature.key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 6) {
                    Text(feature.title)
                    if feature.isRecommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.18), in: Capsule())
                    }
                }
            }
            Text(feature.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
