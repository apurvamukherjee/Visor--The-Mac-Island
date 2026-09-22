import SwiftUI

/// The command palette, drawn inside the island.
///
/// No `TextField`. The panel takes keystrokes through `NotchContentView`'s
/// `keyDown` and the query lives in the store, so there is no SwiftUI focus
/// to win or lose inside a non-activating panel — the one part of this that
/// would have been fiddly.
struct ExpandedPaletteView: View {
    let query: String
    let results: [PaletteCommand]
    let selection: Int
    let windowStart: Int
    let shortcuts: PaletteShortcuts
    /// Whether a bare keypress runs a row right now. The badges are drawn
    /// exactly when this is true, so what the keys do is never a guess.
    let showsShortcuts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.block) {
            queryLine
            if results.isEmpty {
                Text("No commands match")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: IslandSpacing.row) {
                    ForEach(Array(visibleResults.enumerated()), id: \.element.id) { index, command in
                        row(command, isSelected: index + windowStart == selection, row: index + 1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var visibleResults: [PaletteCommand] {
        Array(results.dropFirst(windowStart).prefix(IslandLayout.maxPaletteRows))
    }

    private func keyBadge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .frame(minWidth: 16, minHeight: 15)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }

    private var queryLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(query.isEmpty ? "Run a command" : query)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(query.isEmpty ? .white.opacity(0.35) : .white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: IslandLayout.Block.paletteQuery)
    }

    private func row(_ command: PaletteCommand, isSelected: Bool, row: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: command.symbol)
                .font(.system(size: 11))
                .frame(width: 16)
            Text(command.title)
                .font(.system(size: 12, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
            if showsShortcuts {
                // The command's own letter if it has one, else the row
                // number, which always works and needs no setting up.
                keyBadge(shortcuts.key(for: command.id).map(String.init) ?? "\(row)")
            }
        }
        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.6))
        .padding(.horizontal, 8)
        .frame(height: IslandLayout.Block.paletteRow)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(isSelected ? 0.14 : 0))
        )
    }
}
