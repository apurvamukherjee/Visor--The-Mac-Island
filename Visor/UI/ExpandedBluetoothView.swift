import SwiftUI

/// A device connecting or dropping. Same shape as the battery alert, because
/// it is the same kind of announcement: one glyph, one line, one detail.
struct ExpandedBluetoothView: View {
    let alert: BluetoothAlert

    var body: some View {
        HStack(alignment: .center, spacing: IslandSpacing.column) {
            Image(systemName: alert.symbolName)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(alert.tint)
                .frame(width: IslandLayout.Column.alertIcon)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(alert.detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}
