import SwiftUI

/// The drawn battery beside a low/full alert, ported from the reference's
/// `LowPowerNotchView`/`FullPowerNotchView` indicators.
///
/// The reference pulses with `.repeatForever`, which Visor's power rules
/// forbid: an animation with no end keeps the view graph running for as long
/// as the island is open. A battery alert is a peek of a few seconds, so the
/// pulse is a **fixed repeat count** instead — it reads as the same breathing
/// warning and then stops on its own. Reduce Motion drops it to none.
struct BatteryLevelIndicator: View {
    let alert: BatteryAlert

    @State private var pulse = false

    /// Enough breaths to read as a pulse across the peek, and no more.
    private static let pulseCount = 3
    private static let pulseDuration: Double = 1

    private var fill: Double {
        switch alert {
        case let .low(percentage): Double(percentage) / 100
        case .full: 1
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(alert.tint.opacity(0.2))
                .frame(width: 75, height: 45)

            shell

            level
        }
        .onAppear(perform: startPulse)
    }

    /// The empty casing: body plus the terminal nub.
    private var shell: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(alert.tint.opacity(0.4))
                .frame(width: 40, height: 24)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(alert.tint.opacity(0.4))
                .frame(width: 3, height: 8)
        }
        .padding(.trailing, 5)
    }

    /// The charge itself, sized to the real percentage rather than the
    /// reference's fixed bar — a "Low 8%" that draws the same width as a
    /// "Low 20%" is telling you something it doesn't know.
    private var level: some View {
        let width = max(4, 40 * fill)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(alert.tint.gradient)
                .frame(width: width, height: 14)
                .opacity(pulse ? 1 : 0.3)

            // Only the low alert gets the expanding halo — a full battery is
            // good news and does not need to throb at you.
            if case .low = alert {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(alert.tint.opacity(0.9).gradient, lineWidth: 1.5)
                    .frame(width: pulse ? width : 30, height: pulse ? 14 : 32)
                    .opacity(pulse ? 0.3 : 1)
            }
        }
        // Left-aligned in the casing, so the charge grows from the terminal
        // end the way a real one does.
        .frame(width: 40, alignment: .leading)
        .offset(x: -15)
    }

    private func startPulse() {
        guard !Motion.reduceMotion else {
            pulse = true
            return
        }
        withAnimation(
            .easeInOut(duration: Self.pulseDuration)
                .repeatCount(Self.pulseCount * 2, autoreverses: true)
        ) {
            pulse = true
        }
    }
}
