import IOKit.ps
import SwiftUI
import Testing
@testable import Visor

struct BatteryInfoParserTests {
    @Test
    func parsesPercentageAndChargingState() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey as String: 72,
            kIOPSIsChargingKey as String: true
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

struct BatteryGlyphTests {
    @Test
    func chargingAlwaysReadsBoltRegardlessOfPercentage() {
        #expect(BatteryGlyph.symbolName(percentage: 5, isCharging: true) == "bolt.fill")
        #expect(BatteryGlyph.tint(percentage: 5, isCharging: true) == .yellow)
    }

    @Test
    func symbolTierBoundaries() {
        #expect(BatteryGlyph.symbolName(percentage: 100, isCharging: false) == "battery.100")
        #expect(BatteryGlyph.symbolName(percentage: 76, isCharging: false) == "battery.100")
        #expect(BatteryGlyph.symbolName(percentage: 75, isCharging: false) == "battery.75")
        #expect(BatteryGlyph.symbolName(percentage: 51, isCharging: false) == "battery.75")
        #expect(BatteryGlyph.symbolName(percentage: 50, isCharging: false) == "battery.50")
        #expect(BatteryGlyph.symbolName(percentage: 26, isCharging: false) == "battery.50")
        #expect(BatteryGlyph.symbolName(percentage: 25, isCharging: false) == "battery.25")
        #expect(BatteryGlyph.symbolName(percentage: 11, isCharging: false) == "battery.25")
        #expect(BatteryGlyph.symbolName(percentage: 10, isCharging: false) == "battery.0")
        #expect(BatteryGlyph.symbolName(percentage: 0, isCharging: false) == "battery.0")
    }

    @Test
    func tintTierBoundaries() {
        #expect(BatteryGlyph.tint(percentage: 21, isCharging: false) == .white)
        #expect(BatteryGlyph.tint(percentage: 20, isCharging: false) == .orange)
        #expect(BatteryGlyph.tint(percentage: 11, isCharging: false) == .orange)
        #expect(BatteryGlyph.tint(percentage: 10, isCharging: false) == .red)
    }
}
