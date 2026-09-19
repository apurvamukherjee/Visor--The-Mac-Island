import SwiftUI

/// The scrub bar. `TimelineView` recomputes the fill from the stored anchor
/// the same way `ExpandedTimerView` recomputes its countdown — nothing ticks
/// behind a closed or paused island, and the position is derived rather than
/// accumulated. Dragging overrides the anchor with a local optimistic value,
/// the same trick `ExpandedVolumeView`'s bar uses, because `setTime` has to
/// round-trip through the adapter before the anchor would otherwise catch up
/// to the pointer.
struct NowPlayingSeekBar: View {
    let progress: NowPlayingProgress
    /// The album's colour, for the `.artwork` tint style. Nil until the
    /// artwork has been decoded.
    var tint: Color?
    var onSeek: (TimeInterval) -> Void

    @AppStorage(Preferences.progressTintKey) private var tintStyle = ProgressTintStyle.standard.rawValue

    private var fillColor: Color {
        (ProgressTintStyle(rawValue: tintStyle) ?? .standard).resolved(tint: tint)
    }

    @State private var dragElapsed: TimeInterval?

    private static let barHeight: CGFloat = 3
    private static let draggingBarHeight: CGFloat = 5
    private static let tickInterval: TimeInterval = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tickInterval)) { context in
            let elapsed = dragElapsed ?? progress.elapsed(at: context.date)
            HStack(spacing: 6) {
                Text(Self.format(elapsed))
                    .frame(width: 22, alignment: .trailing)
                bar(elapsed: elapsed)
                Text(Self.format(progress.duration))
                    .frame(width: 22, alignment: .leading)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func bar(elapsed: TimeInterval) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = progress.duration > 0 ? elapsed / progress.duration : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(fillColor)
                    .frame(width: width * CGFloat(fraction))
            }
            // The whole track is the target, not just the filled part —
            // matches `ExpandedVolumeView`'s bar.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let target = min(max(0, value.location.x / max(width, 1)), 1) * progress.duration
                        dragElapsed = target
                        onSeek(target)
                    }
                    .onEnded { _ in dragElapsed = nil }
            )
            .animation(dragElapsed == nil ? Motion.resolved(Motion.layout) : nil, value: fraction)
        }
        .frame(height: dragElapsed == nil ? Self.barHeight : Self.draggingBarHeight)
        .animation(Motion.resolved(Motion.layout), value: dragElapsed != nil)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
