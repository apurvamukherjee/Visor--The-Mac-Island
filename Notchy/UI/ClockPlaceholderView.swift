import SwiftUI

/// Minute resolution and a small font — this sits in the strip that flanks
/// the camera housing in the expanded view, which is narrower than the
/// hardware notch itself.
struct ClockPlaceholderView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
    }
}
