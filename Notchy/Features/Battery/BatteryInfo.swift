import IOKit.ps

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
