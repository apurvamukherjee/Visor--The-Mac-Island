import Testing
@testable import Visor

struct DeviceBatteryTests {
    /// Longest name first, or "AirPods Pro" falls into the plain AirPods
    /// case and wears the wrong glyph.
    @Test
    func glyphMatchesTheLongestProductNameFirst() {
        #expect(DeviceBatteryGlyph.symbolName(for: "AirPods Pro") == "airpodspro")
        #expect(DeviceBatteryGlyph.symbolName(for: "AirPods Max") == "airpods.max")
        #expect(DeviceBatteryGlyph.symbolName(for: "Apurva's AirPods") == "airpods")
        #expect(DeviceBatteryGlyph.symbolName(for: "Magic Mouse") == "magicmouse")
        #expect(DeviceBatteryGlyph.symbolName(for: "Magic Keyboard") == "keyboard")
        #expect(DeviceBatteryGlyph.symbolName(for: "Some Headset") == "antenna.radiowaves.left.and.right")
    }

    /// The lower bud is what you have left; the case is not charge you can
    /// use while wearing them.
    @Test
    func theLowerBudWins() {
        #expect(DeviceBatteryReader.percentage(combined: nil, left: 80, right: 45, single: nil) == 45)
        #expect(DeviceBatteryReader.percentage(combined: 70, left: 80, right: 45, single: nil) == 70)
        #expect(DeviceBatteryReader.percentage(combined: nil, left: nil, right: nil, single: 62) == 62)
    }

    /// Zero means "not reported" in this registry, not "flat" — reading it
    /// as a real value would peek 0% at every accessory that stays quiet.
    @Test
    func zeroMeansUnreportedAndFallsThrough() {
        #expect(DeviceBatteryReader.percentage(combined: 0, left: 0, right: 55, single: 0) == 55)
        #expect(DeviceBatteryReader.percentage(combined: 0, left: 0, right: 0, single: 0) == nil)
        #expect(DeviceBatteryReader.percentage(combined: nil, left: nil, right: nil, single: nil) == nil)
    }

    @Test
    func tintWarnsOnlyWhenItIsActuallyLow() {
        #expect(DeviceBattery(product: "AirPods", percentage: 90).tint == .white)
        #expect(DeviceBattery(product: "AirPods", percentage: 25).tint == .orange)
        #expect(DeviceBattery(product: "AirPods", percentage: 9).tint == .red)
    }
}
