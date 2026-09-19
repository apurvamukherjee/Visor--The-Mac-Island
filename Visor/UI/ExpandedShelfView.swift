import AppKit
import SwiftUI

/// Expanded, one or more catches waiting: a row of thumbnails, each
/// draggable and individually dismissable, with a count and a clear-all.
struct ExpandedShelfView: View {
    let shelf: [ScreenshotCatch]
    var onOpen: (ScreenshotCatch) -> Void
    var onDismiss: (ScreenshotCatch) -> Void
    var onDropCompleted: (ScreenshotCatch) -> Void
    var onClearAll: () -> Void

    private static let tileHeight: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.block) {
            header
            // Centred, not left-aligned behind a trailing spacer: a chip is
            // as wide as its screenshot's aspect ratio makes it, so the row
            // cannot be sized in advance, and a single catch pinned left in
            // a four-catch island read as a mistake.
            HStack(spacing: IslandSpacing.tile) {
                ForEach(shelf) { shot in
                    ScreenshotChip(
                        shot: shot,
                        height: Self.tileHeight,
                        onOpen: { onOpen(shot) },
                        onDismiss: { onDismiss(shot) },
                        onDropCompleted: { onDropCompleted(shot) }
                    )
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .animation(Motion.resolved(Motion.catchIn), value: shelf)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(shelf.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: Double(shelf.count)))
            Spacer(minLength: 0)
            Button(action: onClearAll) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("All")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
    }
}
