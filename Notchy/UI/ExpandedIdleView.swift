import SwiftUI

/// Expanded, nothing playing: the day's agenda in two columns, with the date
/// block leading the left column.
struct ExpandedIdleView: View {
    let events: [CalendarEvent]
    /// Height of the real camera housing. The left column opens with the
    /// narrow date block, which sits clear of the housing on its own, but the
    /// right column's first chip is wide enough to run under it — so that
    /// column starts below the housing instead.
    let housingHeight: CGFloat

    private static let shownLimit = 4

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                DateBlock()
                ForEach(leftColumn) { EventRow(event: $0) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rightColumn) { EventRow(event: $0) }
                if overflow > 0 {
                    overflowRow
                }
                Spacer(minLength: 0)
                SignatureGlow()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, housingHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shown: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.shownLimit)
    }

    /// The date block occupies the left column's first slot, so the split is
    /// deliberately uneven — fewer events on the left, not half and half.
    private var leftColumn: [CalendarEvent] {
        Array(shown.prefix(2))
    }

    private var rightColumn: [CalendarEvent] {
        Array(shown.dropFirst(2))
    }

    private var overflow: Int {
        CalendarEventMapper.overflowCount(total: events.count, shown: shown.count)
    }

    private var overflowRow: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.35))
                .frame(width: 3, height: 16)
            Text("\(overflow) more event\(overflow == 1 ? "" : "s")")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}
