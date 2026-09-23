import SwiftUI

/// The second settings tab: everything the feature program adds that changes
/// how the island already behaves, each one off until it is asked for.
///
/// Separate from the Settings tab on purpose. These are not preferences
/// between equally-shipped options — they are changes to a working app, and
/// mixing them into the existing column would bury that distinction under a
/// twelfth section.
///
/// `Form`/`.grouped`, like every other pane. This was a hand-rolled
/// `ScrollView` of `VStack`s and `Divider`s, which gave the sidebar two panes
/// that looked like inset cards and two that looked like a plain document —
/// in one window, a click apart.
struct NewFeaturesView: View {
    var body: some View {
        Form {
            Section {
                ForEach(NewFeatures.all) { feature in
                    // Disabled rather than hidden: a row that appears and
                    // vanishes under the cursor is worse than one that greys
                    // out.
                    NewFeatureRow(feature: feature)
                        .disabled(
                            feature.key == NewFeatures.islandStackTint.key
                                && pagingStyle != PagingStyle.cardStack.rawValue
                        )
                }
            } footer: {
                Text("Nothing here is on until you turn it on. With every switch off, "
                    + "Visor behaves exactly as it always has.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledSlider(
                    "Hover delay",
                    value: $hoverDelay,
                    range: Preferences.hoverIntentDelayRange,
                    format: { "\(Int($0)) ms" }
                )
            } header: {
                Text("Hover")
            } footer: {
                Text("How long the pointer rests on the island before it opens. "
                    + "120 ms is the default.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Paging style", selection: $pagingStyle) {
                    ForEach(PagingStyle.allCases, id: \.rawValue) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                LabeledSlider(
                    "Chin reveal delay",
                    value: $stackReveal,
                    range: Preferences.stackRevealDelayRange,
                    format: { "\(Int($0)) ms" }
                )
                .disabled(pagingStyle != PagingStyle.cardStack.rawValue)
            } header: {
                Text("Paging")
            } footer: {
                Text("How the island moves between its screens, and how long after it "
                    + "opens the chins slide out. 0 ms shows them straight away. "
                    + "Needs “Swipe between screens” on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(AIUsageTool.allCases, id: \.rawValue) { tool in
                    BudgetField(tool: tool)
                }
            } header: {
                Text("Daily token budget")
            } footer: {
                Text("Optional. Set a target and the badge shows how far through it you are. "
                    + "Left empty it just shows the count — there is no way to read your real "
                    + "plan limit from this Mac, so the badge never pretends to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// The one value in this tab rather than a switch: hover delay has a
    /// number, not an off position, so it cannot ride `NewFeature`'s "unset
    /// means today's behaviour" guarantee and carries its own default.
    @AppStorage(Preferences.hoverIntentDelayKey)
    private var hoverDelay = Preferences.hoverIntentDelayDefault

    /// The one *value* setting among the switches, for the same reason as
    /// the hover delay: a style has no off position, so it carries its own
    /// default rather than riding `bool(forKey:)`'s false.
    @AppStorage(Preferences.pagingStyleKey) private var pagingStyle = PagingStyle.crossFade.rawValue
    @AppStorage(Preferences.stackRevealDelayKey)
    private var stackReveal = Preferences.stackRevealDelayDefault
}

/// One tool's target. Empty is the shipped state and means no percentage is
/// drawn at all — these are *your* numbers, since neither vendor publishes a
/// real plan limit anywhere this machine can read.
private struct BudgetField: View {
    let tool: AIUsageTool

    @AppStorage private var budget: Int

    init(tool: AIUsageTool) {
        self.tool = tool
        _budget = AppStorage(wrappedValue: 0, Preferences.dailyTokenBudgetKey(for: tool))
    }

    var body: some View {
        LabeledContent(tool.title) {
            TextField(
                "",
                value: $budget,
                format: .number.grouping(.automatic),
                prompt: Text("None")
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 110)
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
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
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
                Text(feature.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
