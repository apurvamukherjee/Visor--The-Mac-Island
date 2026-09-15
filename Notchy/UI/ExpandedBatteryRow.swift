import SwiftUI

struct ExpandedBatteryRow: View {
    let info: BatteryInfo

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: info.isCharging ? "bolt.fill" : "battery.100")
                .foregroundStyle(info.isCharging ? .yellow : .white)
            Text("\(info.percentage)%")
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
    }
}
