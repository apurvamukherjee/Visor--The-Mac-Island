import SwiftUI

/// Expanded, nothing playing: the date block beside the day's agenda, with
/// the timer presets underneath.
///
/// This was two columns that split the events between them. At three events
/// it balanced; at zero — the common case by the evening — it left a screen
/// of black with a stray "2 more events" floating in it, because the
/// overflow counted every event of the day rather than the ones still to
/// come. One column, an explicit empty state, and an island that shrinks to
/// fit replace all of it.
struct ExpandedIdleView: View {
    let events: [CalendarEvent]
    var onStartTimer: ((TimeInterval) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.block) {
            HStack(alignment: .top, spacing: IslandSpacing.column) {
                DateBlock()
                    .frame(width: IslandLayout.Column.date, alignment: .leading)
                agenda
            }
            if let onStartTimer {
                TimerPresetRow(onStart: onStartTimer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var agenda: some View {
        if shown.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: IslandSpacing.row) {
                ForEach(shown) { EventRow(event: $0) }
                if overflow > 0 {
                    overflowRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shown: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: IslandLayout.maxEventRows)
    }

    /// Counted against what is still upcoming, not against the whole day.
    private var overflow: Int {
        CalendarEventMapper.upcomingCount(events, now: .now) - shown.count
    }

    /// Reads as finished rather than broken: an empty agenda at 9pm is the
    /// normal state, and an agenda that says nothing at all looks like the
    /// calendar failed to load.
    private var emptyState: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            Text(events.isEmpty ? "Nothing scheduled" : "Nothing left today")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: IslandLayout.Block.emptyAgenda, alignment: .center)
    }

    private var overflowRow: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.35))
                .frame(width: 3, height: 14)
            Text("\(overflow) more")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}
