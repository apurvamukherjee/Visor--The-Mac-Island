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
        // Tinted fill keyed to the calendar's own colour, like the reference
        // design — a bare left bar on black read as unfinished.
        .background(barColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }

    private var barColor: Color {
        event.colorHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var timeLabel: String {
        event.isAllDay
            ? "All day"
            : event.start.formatted(date: .omitted, time: .shortened)
    }
}

extension Color {
    /// `#RRGGBB` only — the single format `CalendarService` emits.
    init?(hex: String) {
        var value = UInt64.zero
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else {
            return nil
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
