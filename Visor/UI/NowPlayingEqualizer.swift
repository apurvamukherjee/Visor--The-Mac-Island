import SwiftUI

/// The bouncing bars beside the artwork.
///
/// Honest about what it is: decorative. There is no public API that gives an
/// app the system's audio levels, so the reference's equaliser animated
/// random heights too — this one does the same, and says so here rather than
/// implying it is reacting to the music.
///
/// Built on `PlaybackBars`' rule rather than its own: never animate a layout
/// property in a loop (RESEARCH §5.1b). The bars scale a fixed-height
/// rectangle, which is a render-tree change, not a layout pass.
struct NowPlayingEqualizer: View {
    let isPlaying: Bool
    let tint: Color?

    private static let barCount = 4
    private static let barWidth: CGFloat = 2.5
    private static let height: CGFloat = 16
    /// Each bar runs at its own period so they never march in lockstep.
    private static let periods: [Double] = [0.62, 0.48, 0.71, 0.55]

    var body: some View {
        // Reduce Motion stops the whole thing rather than slowing it: a
        // decorative animation is the first thing that should go.
        if Motion.reduceMotion || !isPlaying {
            staticBars
        } else {
            TimelineView(.animation) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0 ..< Self.barCount, id: \.self) { index in
                        bar(scale: Self.scale(at: seconds, bar: index))
                    }
                }
                .frame(height: Self.height)
            }
        }
    }

    private var staticBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< Self.barCount, id: \.self) { _ in
                bar(scale: 0.35)
            }
        }
        .frame(height: Self.height)
    }

    private func bar(scale: CGFloat) -> some View {
        Capsule()
            .fill(tint ?? .white)
            .frame(width: Self.barWidth, height: Self.height)
            // Scale, not `frame(height:)`: a height is a layout property,
            // and animating one every frame re-runs the view graph — the
            // exact bug the power pass measured at 5% CPU.
            .scaleEffect(y: scale, anchor: .bottom)
    }

    /// A sine per bar, offset so they drift apart. Pure so the motion can be
    /// checked without a running clock.
    static func scale(at seconds: Double, bar index: Int) -> CGFloat {
        let period = periods[index % periods.count]
        let phase = Double(index) * 0.8
        let wave = sin(seconds / period * 2 * .pi + phase)
        // 0.25...1, so a bar never collapses to nothing.
        return CGFloat(0.625 + 0.375 * wave)
    }
}
