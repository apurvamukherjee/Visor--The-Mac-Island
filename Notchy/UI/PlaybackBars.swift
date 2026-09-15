import SwiftUI

/// The Dynamic Island's bouncing bars. Decorative, not a spectrum analyser —
/// macOS gives no access to another app's audio, so anything "reactive" here
/// would be a lie. Staggered phases read as music without pretending to be
/// data.
///
/// Core Animation drives the loop on the render server: no timer, no
/// per-frame SwiftUI work. It still only exists while something is playing,
/// and stops dead when playback pauses, per the power rules.
struct PlaybackBars: View {
    var isPlaying: Bool
    var height: CGFloat = 12

    /// Environment, not a one-shot read of `Motion.reduceMotion`: the system
    /// setting can be switched on mid-track, and the bars are the only
    /// unbounded animation in the app — they have to stop when it is.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBouncing = false

    private static let barCount = 4
    private static let barWidth: CGFloat = 2
    private static let restingScale: CGFloat = 0.35
    /// Each bar lags the one before it, which is what stops the row reading
    /// as a single block pulsing.
    private static let stagger = 0.13

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0 ..< Self.barCount, id: \.self) { index in
                Capsule()
                    .frame(width: Self.barWidth, height: barHeight(index))
                    .animation(animation(index), value: isBouncing)
            }
        }
        .frame(height: height)
        .onAppear { updateBounce() }
        .onChange(of: isPlaying) { _, _ in updateBounce() }
        .onChange(of: reduceMotion) { _, _ in updateBounce() }
    }

    private func updateBounce() {
        isBouncing = isPlaying && !reduceMotion
    }

    /// Bars at rest sit at staggered heights rather than flat, so a paused
    /// track still reads as a track.
    private func barHeight(_ index: Int) -> CGFloat {
        let tall = index.isMultiple(of: 2) ? 0.6 : 1.0
        return height * (isBouncing ? tall : Self.restingScale + CGFloat(index) * 0.08)
    }

    private func animation(_ index: Int) -> Animation? {
        guard isBouncing else { return Motion.resolved(Motion.contentOut) }
        return Motion.beat
            .repeatForever(autoreverses: true)
            .delay(Double(index) * Self.stagger)
    }
}
