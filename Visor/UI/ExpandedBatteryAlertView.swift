import SwiftUI

/// Expanded, battery crossed a threshold worth saying out loud. The Low
/// Power Mode toggle DynamicNotch shows is deliberately absent: flipping it
/// needs an admin `pmset` call, and Visor asks for no privileges it can
/// avoid — so this points at Settings instead of pretending.
struct ExpandedBatteryAlertView: View {
    let alert: BatteryAlert

    var body: some View {
        HStack(alignment: .center, spacing: IslandSpacing.column) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(alert.detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    // Two lines is what the island reserves; a third would
                    // be clipped by the shape rather than shown.
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // The drawn battery sits on the trailing edge, as the reference
            // has it: the text says what happened, the indicator shows it.
            BatteryLevelIndicator(alert: alert)
                .transition(.island)
        }
        .foregroundStyle(.white)
    }
}
