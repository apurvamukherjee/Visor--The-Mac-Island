import SwiftUI

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
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
