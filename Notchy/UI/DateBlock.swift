import SwiftUI

/// The reference design's date treatment: a small tinted weekday sitting on
/// top of a large day number. Shared by both expanded layouts so the idle
/// and music-live states read as the same design.
struct DateBlock: View {
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: -4) {
            Text(Date.now, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.35))
                .textCase(.uppercase)
            Text(Date.now, format: .dateTime.day())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
