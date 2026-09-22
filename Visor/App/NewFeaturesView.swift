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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
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
            Toggle(feature.title, isOn: $isOn)
            Text(feature.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
