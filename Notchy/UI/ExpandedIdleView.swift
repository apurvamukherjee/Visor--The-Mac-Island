import SwiftUI

/// Expanded, nothing playing: the day's full agenda in two columns.
struct ExpandedIdleView: View {
    let events: [CalendarEvent]

    private static let shownLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if shown.isEmpty {
                Text("Nothing scheduled")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                columns
            }
            if overflow > 0 {
                Text("+\(overflow) more event\(overflow == 1 ? "" : "s")")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var shown: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.shownLimit)
    }

    private var overflow: Int {
        CalendarEventMapper.overflowCount(total: events.count, shown: shown.count)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date.now, format: .dateTime.weekday(.abbreviated).day())
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            SignatureGlow()
        }
    }

    private var columns: some View {
        let half = (shown.count + 1) / 2
        return HStack(alignment: .top, spacing: 12) {
            column(Array(shown.prefix(half)))
            column(Array(shown.dropFirst(half)))
        }
    }

    private func column(_ events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(events) { EventRow(event: $0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
