import SwiftUI

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 7) {
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 2,
                bottomTrailingRadius: 2,
                topTrailingRadius: 2
            )
            .fill(barColor)
            .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(barColor)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(barColor.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        // Tinted fill keyed to the calendar's own colour — a bare left bar on
        // black read as unfinished. Kept very low (0.14 lifted the chip into
        // a visible grey-purple panel against the pure-black surface): the
        // colour bar and the text carry the identity, the fill only has to
        // hint at a container.
        .background(barColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
    }

    private var barColor: Color {
        event.color ?? .accentColor
    }

    private var timeLabel: String {
        event.isAllDay
            ? "All day"
            : event.start.formatted(date: .omitted, time: .shortened)
    }
}
