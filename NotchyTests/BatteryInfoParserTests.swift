import IOKit.ps
import Testing
@testable import Notchy

struct BatteryInfoParserTests {
    @Test
    func parsesPercentageAndChargingState() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey as String: 72,
            kIOPSIsChargingKey as String: true,
        ]
        let info = BatteryInfoParser.parse(description)
        #expect(info == BatteryInfo(percentage: 72, isCharging: true))
    }

    @Test
    func missingChargingKeyDefaultsToFalse() {
        let description: [String: Any] = [kIOPSCurrentCapacityKey as String: 40]
        #expect(BatteryInfoParser.parse(description) == BatteryInfo(percentage: 40, isCharging: false))
    }

    @Test
    func missingPercentageReturnsNil() {
        let description: [String: Any] = [kIOPSIsChargingKey as String: true]
        #expect(BatteryInfoParser.parse(description) == nil)
    }
}
