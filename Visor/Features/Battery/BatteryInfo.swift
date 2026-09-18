import IOKit.ps
import SwiftUI

struct BatteryInfo: Equatable {
    let percentage: Int
    let isCharging: Bool
}

enum BatteryInfoParser {
    static func parse(_ description: [String: Any]) -> BatteryInfo? {
        guard let percentage = description[kIOPSCurrentCapacityKey as String] as? Int else {
            return nil
        }
        let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        return BatteryInfo(percentage: percentage, isCharging: isCharging)
    }
}

/// Tiers the compact-wing glyph the way macOS's own Control Center battery
/// does, so a glance at the wing reads the same as a glance at the menu bar.
enum BatteryGlyph {
    static func symbolName(percentage: Int, isCharging: Bool) -> String {
        guard !isCharging else { return "bolt.fill" }
        return switch percentage {
        case ..<11: "battery.0"
        case ..<26: "battery.25"
        case ..<51: "battery.50"
        case ..<76: "battery.75"
        default: "battery.100"
        }
    }

    static func tint(percentage: Int, isCharging: Bool) -> Color {
        guard !isCharging else { return .yellow }
        return switch percentage {
        case ..<11: .red
        case ..<21: .orange
        default: .white
        }
    }
}
