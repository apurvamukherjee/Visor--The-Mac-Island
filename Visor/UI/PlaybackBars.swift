import AppKit
import SwiftUI

/// The Dynamic Island's bouncing bars. Decorative, not a spectrum analyser —
/// macOS gives no access to another app's audio, so anything "reactive" here
/// would be a lie. Staggered phases read as music without pretending to be
/// data.
///
/// Backed by `CALayer` rather than animated SwiftUI views on purpose. The
/// SwiftUI version animated `frame(height:)`, which is a *layout* property:
/// every frame invalidated layout and re-ran the view graph on the main
/// thread, which measured at ~4% CPU for the whole app. These animations are
/// handed to the render server once and cost the main thread nothing until
/// playback stops.
struct PlaybackBars: View {
    var isPlaying: Bool
    var height: CGFloat = 12
    /// The album's colour, the way the iPhone tints its waveform. White when
    /// the cover has no colour worth using, or when the user has asked for
    /// increased contrast.
    var tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedTint: Color {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .white : (tint ?? .white)
    }

    var body: some View {
        Bars(isBouncing: isPlaying && !reduceMotion, height: height, tint: resolvedTint)
            // A representable has no opinion about its size, so without this
            // SwiftUI hands it every point on offer — which stretched the
            // expanded scrim across the whole album cover.
            .frame(width: PlaybackBarsView.intrinsicWidth, height: height)
            .fixedSize()
    }

    private struct Bars: NSViewRepresentable {
        var isBouncing: Bool
        var height: CGFloat
        var tint: Color

        func makeNSView(context _: Context) -> PlaybackBarsView {
            PlaybackBarsView()
        }

        func updateNSView(_ view: PlaybackBarsView, context _: Context) {
            view.setTint(NSColor(tint))
            view.setBouncing(isBouncing)
        }

        func sizeThatFits(_: ProposedViewSize, nsView _: PlaybackBarsView, context _: Context) -> CGSize? {
            CGSize(width: PlaybackBarsView.intrinsicWidth, height: height)
        }

        @MainActor
        static func dismantleNSView(_ view: PlaybackBarsView, coordinator _: ()) {
            view.setBouncing(false)
        }
    }
}

/// Four capsules that scale about their centres. Scale, not height, so the
/// animation is a layer transform the compositor owns outright.
@MainActor
final class PlaybackBarsView: NSView {
    private static let barCount = 4
    private static let barWidth: CGFloat = 2
    private static let spacing: CGFloat = 2
    private static let restingScale = 0.35
    private static let animationKey = "beat"
    /// Each bar lags the one before it, which is what stops the row reading
    /// as a single block pulsing.
    private static let stagger = 0.13
    private static let beatDuration = 0.42

    static let intrinsicWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing

    private var bars: [CALayer] = []
    private var isBouncing = false
    private var tint = NSColor.white

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        bars = (0 ..< Self.barCount).map { _ in
            let bar = CALayer()
            bar.backgroundColor = tint.cgColor
            bar.cornerRadius = Self.barWidth / 2
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            return bar
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.intrinsicWidth, height: NSView.noIntrinsicMetric)
    }

    /// Laid out from `bounds`, not from init: the view is sized by SwiftUI
    /// after creation, and at two different heights (compact wing, expanded
    /// artwork). Implicit animations are off, or every layout pass would
    /// animate the bars sliding into place.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
            bar.position = CGPoint(
                x: CGFloat(index) * (Self.barWidth + Self.spacing) + Self.barWidth / 2,
                y: bounds.midY
            )
            if !isBouncing {
                bar.setValue(Self.restingHeightScale(index), forKeyPath: "transform.scale.y")
            }
        }
        CATransaction.commit()
    }

    /// Matched to the artwork flip's second half so colour and cover land on
    /// the same frame — a separate, differently-timed fade reads as a glitch.
    func setTint(_ newTint: NSColor) {
        guard newTint != tint else { return }
        tint = newTint
        CATransaction.begin()
        CATransaction.setAnimationDuration(Motion.artFlipInDuration)
        for bar in bars {
            bar.backgroundColor = newTint.cgColor
        }
        CATransaction.commit()
    }

    func setBouncing(_ bouncing: Bool) {
        guard bouncing != isBouncing else { return }
        isBouncing = bouncing
        guard bouncing else {
            bars.forEach { $0.removeAnimation(forKey: Self.animationKey) }
            needsLayout = true
            return
        }
        let start = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            let beat = CABasicAnimation(keyPath: "transform.scale.y")
            beat.fromValue = Self.restingHeightScale(index)
            beat.toValue = index.isMultiple(of: 2) ? 0.6 : 1.0
            beat.duration = Self.beatDuration
            beat.autoreverses = true
            beat.repeatCount = .infinity
            beat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beat.beginTime = start + Double(index) * Self.stagger
            bar.add(beat, forKey: Self.animationKey)
        }
    }

    /// Bars at rest sit at staggered heights rather than flat, so a paused
    /// track still reads as a track.
    private static func restingHeightScale(_ index: Int) -> Double {
        restingScale + Double(index) * 0.08
    }
}
