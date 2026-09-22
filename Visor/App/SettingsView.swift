import SwiftUI

/// The app's only window: a sidebar down the left, one pane on the right.
///
/// Static by design — the power rules forbid anything that animates or ticks,
/// and nothing here does. Every pane reads its keys through `@AppStorage`, so
/// a change lands on the island while this window is still open.
struct SettingsView: View {
    var store: NotchStore

    @State private var pane: SettingsPane? = .general
    /// Bumped by "Restore original settings". Applied as the detail pane's
    /// `.id`, which rebuilds it — and a rebuilt `@AppStorage` re-reads its
    /// key, so cleared keys show their defaults again. The panes each own
    /// their own wrappers now, so the old approach of assigning every value
    /// back by hand would have to reach across four views to do it.
    @State private var restoreToken = 0

    private var selected: SettingsPane {
        pane ?? .general
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 210)
        } detail: {
            detail
                .id(restoreToken)
                .navigationTitle(selected.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .general:
            SettingsGeneralView(store: store, onRestore: restore)
        case .appearance:
            SettingsAppearanceView(store: store)
        case .nowPlaying:
            SettingsNowPlayingView()
        case .features:
            NewFeaturesView()
        case .shortcuts:
            ShortcutsView()
        }
    }

    /// Clears the stored keys, then rebuilds the pane so its wrappers re-read
    /// them. `Motion.preset` and the store's trim are caches of those same
    /// keys rather than readers of them, so both are refreshed by hand.
    private func restore() {
        Preferences.restoreDefaults()
        Motion.preset = .balanced
        store.notchWidthOffset = 0
        store.notchHeightOffset = 0
        store.previewNotchSize()
        restoreToken += 1
    }
}

/// A slider with its label and current value above it — `Slider`'s own label
/// sits beside the track and squeezes it to nothing at a settings column's
/// width.
struct LabeledSlider: View {
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
            Slider(value: $value, in: range)
        }
    }
}
