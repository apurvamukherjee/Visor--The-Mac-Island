import SwiftUI

/// Expanded countdown. `TimelineView` is the clock: it only schedules while
/// the view is on screen, so a closed island runs nothing, and the figure
/// is derived from the deadline rather than accumulated — see `IslandTimer`.
struct ExpandedTimerView: View {
    let timer: IslandTimer
    var onTogglePause: () -> Void
    var onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            let finished = remaining <= 0

            HStack(spacing: 14) {
                if !finished {
                    circleButton(
                        systemName: timer.isPaused ? "play.fill" : "pause.fill",
                        tint: .orange,
                        action: onTogglePause
                    )
                }
                circleButton(systemName: "xmark", tint: .white.opacity(0.18), action: onCancel)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(finished ? "Time's up" : "Timer")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(IslandTimer.format(remaining))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(finished ? .white : .orange)
                }
            }
            .foregroundStyle(.white)
        }
    }

    private func circleButton(systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint))
        }
        .buttonStyle(.plain)
    }
}

/// The idle island's timer affordance. Presets rather than a picker: the
/// island is a glance surface, and a duration field would need a keyboard
/// focus the panel deliberately never takes.
struct TimerPresetRow: View {
    var onStart: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(IslandTimer.presets, id: \.label) { preset in
                Button { onStart(preset.duration) } label: {
                    Text(preset.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
