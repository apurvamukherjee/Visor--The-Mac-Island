import SwiftUI

/// A red dot and an elapsed clock while the screen is being recorded.
///
/// The clock is projected from the recording's start date by `TimelineView`,
/// so nothing ticks to keep it true — the same reason the countdown and the
/// lock-screen clock are built this way.
struct ExpandedScreenRecordingView: View {
    let recording: ScreenRecording

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: IslandSpacing.column) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !Motion.reduceMotion)

                Text("Recording")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text(ScreenRecording.formatted(recording.elapsed(at: context.date)))
                    .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}
