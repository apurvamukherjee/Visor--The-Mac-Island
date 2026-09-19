import SwiftUI

/// A connected Bluetooth accessory's charge — AirPods, Magic Mouse, Magic
/// Keyboard.
struct DeviceBattery: Equatable, Sendable {
    let product: String
    let percentage: Int

    var symbolName: String {
        DeviceBatteryGlyph.symbolName(for: product)
    }

    /// Its own thresholds rather than `BatteryGlyph`'s: a feature never
    /// imports another feature, and an accessory at 20% is not the same
    /// news as a laptop at 20%.
    var tint: Color {
        switch percentage {
        case ..<15: .red
        case ..<30: .orange
        default: .white
        }
    }
}

enum DeviceBatteryGlyph {
    /// Matched on the product string IOKit reports, longest name first so
    /// "AirPods Pro" is not caught by the plain "airpods" case.
    static func symbolName(for product: String) -> String {
        let name = product.lowercased()
        return switch true {
        case name.contains("airpods max"): "airpods.max"
        case name.contains("airpods pro"): "airpodspro"
        case name.contains("airpods"): "airpods"
        case name.contains("mouse"): "magicmouse"
        case name.contains("trackpad"): "magictrackpad"
        case name.contains("keyboard"): "keyboard"
        // Headphones before speakers: a "Bluetooth Headset" is a headphone,
        // and several speaker brands put "sound" in a headphone's name too,
        // so the more specific word has to win.
        case name.contains("headphone"),
             name.contains("headset"),
             name.contains("buds"),
             name.contains("beats"),
             name.contains("wh-"),
             name.contains("wf-"): "headphones"
        case name.contains("speaker"),
             name.contains("soundbar"),
             name.contains("homepod"),
             name.contains("boombox"),
             name.contains("jbl"),
             name.contains("sonos"): "hifispeaker.fill"
        default: "antenna.radiowaves.left.and.right"
        }
    }
}

enum DeviceBatteryReader {
    /// AirPods report a bud each plus a case and sometimes a combined
    /// figure; a mouse reports one number. The **lower bud** is what you
    /// actually have left, so that is what the island shows — the case is
    /// deliberately ignored, since a charged case is not charge you have
    /// while wearing them.
    ///
    /// Zero means "not reported" in this registry, not "flat".
    static func percentage(combined: Int?, left: Int?, right: Int?, single: Int?) -> Int? {
        if let combined, combined > 0 {
            return combined
        }
        if let lowest = [left, right].compactMap(\.self).filter({ $0 > 0 }).min() {
            return lowest
        }
        if let single, single > 0 {
            return single
        }
        return nil
    }
}
