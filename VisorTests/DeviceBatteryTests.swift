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
        // Was the fallback until speakers and headphones got their own
        // glyphs; a headset is a headphone, not an unknown accessory.
        #expect(DeviceBatteryGlyph.symbolName(for: "Some Headset") == "headphones")
        #expect(DeviceBatteryGlyph.symbolName(for: "Unknown Gadget") == "antenna.radiowaves.left.and.right")
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

    @Test
    func headphonesAndSpeakersGetTheirOwnGlyphs() {
        #expect(DeviceBatteryGlyph.symbolName(for: "Sony WH-1000XM5") == "headphones")
        #expect(DeviceBatteryGlyph.symbolName(for: "Galaxy Buds Pro") == "headphones")
        #expect(DeviceBatteryGlyph.symbolName(for: "Beats Studio") == "headphones")
        #expect(DeviceBatteryGlyph.symbolName(for: "JBL Flip 6") == "hifispeaker.fill")
        #expect(DeviceBatteryGlyph.symbolName(for: "HomePod mini") == "hifispeaker.fill")
        #expect(DeviceBatteryGlyph.symbolName(for: "Sonos Roam") == "hifispeaker.fill")
    }

    /// The ordering trap: several speaker brands ship headphones too, so the
    /// headphone words are matched first. A "JBL Headphones" that came back
    /// as a speaker would be this test failing.
    @Test
    func headphoneWordsBeatSpeakerBrands() {
        #expect(DeviceBatteryGlyph.symbolName(for: "JBL Headphones") == "headphones")
        #expect(DeviceBatteryGlyph.symbolName(for: "Sonos Headset") == "headphones")
    }

    /// AirPods keep their own glyphs even though they are headphones — the
    /// specific product art is better than the generic pair.
    @Test
    func airPodsKeepTheirOwnGlyphsOverTheGenericPair() {
        #expect(DeviceBatteryGlyph.symbolName(for: "AirPods Pro") == "airpodspro")
        #expect(DeviceBatteryGlyph.symbolName(for: "Beats Fit Pro") == "headphones")
    }
}
