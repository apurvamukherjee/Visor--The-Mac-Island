import SwiftUI

/// The draggable volume bar. Hand-rolled rather than `Slider`: the system
/// control brings macOS chrome into a surface meant to read as iOS, and the
/// bar has to thicken under the pointer the way the Dynamic Island's does.
struct ExpandedVolumeView: View {
    let volume: VolumeInfo
    var onScrub: (Float) -> Void
    var onToggleMute: () -> Void

    @State private var isDragging = false

    /// Slim, whatever height the card has. Sizing the bar from the box was
    /// tried and looked wrong: paging hands the volume screen the player's
    /// 128pt column, and a bar that filled it read as a bulge rather than a
    /// control. The card's extra height is answered by centring the row in
    /// it, not by fattening the bar.
    private static let barHeight: CGFloat = 26
    private static let draggingBarHeight: CGFloat = 32

    private static let glyphColumn: CGFloat = 44
    private static let percentColumn: CGFloat = 50

    var body: some View {
        HStack(spacing: IslandSpacing.column) {
            Button(action: onToggleMute) {
                Image(systemName: VolumeGlyph.symbolName(level: volume.level, isMuted: volume.isMuted))
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.glyphColumn, height: Self.glyphColumn)
            }
            .buttonStyle(.plain)

            bar

            Text("\(volume.percentage)%")
                .font(.system(size: 16, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.numericText(value: Double(volume.percentage)))
                .frame(width: Self.percentColumn, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .animation(Motion.resolved(Motion.textSwap), value: volume.percentage)
    }

    private var bar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(.white)
                    .frame(width: width * CGFloat(volume.effectiveLevel))
            }
            // The whole track is the target, not just the filled part —
            // tapping ahead of the fill jumps there, as it does on iOS.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        onScrub(Float(value.location.x / max(width, 1)))
                    }
                    .onEnded { _ in isDragging = false }
            )
            // Only while the pointer is not driving it: animating the fill
            // during a drag makes the bar lag the cursor.
            .animation(isDragging ? nil : Motion.resolved(Motion.layout), value: volume.effectiveLevel)
        }
        .frame(height: isDragging ? Self.draggingBarHeight : Self.barHeight)
        .animation(Motion.resolved(Motion.layout), value: isDragging)
    }
}
