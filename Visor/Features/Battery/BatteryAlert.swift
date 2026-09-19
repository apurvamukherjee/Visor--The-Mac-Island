import SwiftUI

/// A charge level worth interrupting for, as opposed to the plug/unplug
/// peek `BatteryService` already fires on every transition.
enum BatteryAlert: Equatable, Sendable {
    case low(Int)
    case full

    /// Below this and not charging is worth saying out loud once.
    static let lowThreshold = 20

    /// Pure so the crossing logic is testable without IOKit: an alert fires
    /// only on the edge into the condition, never repeatedly while inside it.
    static func crossing(from previous: BatteryInfo?, to current: BatteryInfo) -> BatteryAlert? {
        if current.isCharging, current.percentage >= 100 {
            let wasFull = (previous?.isCharging ?? false) && (previous?.percentage ?? 0) >= 100
            return wasFull ? nil : .full
        }
        if !current.isCharging, current.percentage <= lowThreshold {
            let wasLow = !(previous?.isCharging ?? true) && (previous?.percentage ?? .max) <= lowThreshold
            return wasLow ? nil : .low(current.percentage)
        }
        return nil
    }

    var title: String {
        switch self {
        case let .low(percentage): "Battery Low  \(percentage)%"
        case .full: "Full Battery  100%"
        }
    }

    /// The wings have room for a couple of words, not a sentence.
    var compactLabel: String {
        switch self {
        case let .low(percentage): "Low  \(percentage)%"
        case .full: "Charged"
        }
    }

    var detail: String {
        switch self {
        case .low: "Connect to power, or turn on Low Power Mode in Settings."
        case .full: "Your Mac is fully charged."
        }
    }

    var symbolName: String {
        switch self {
        case .low: "battery.25"
        case .full: "battery.100.bolt"
        }
    }

    var tint: Color {
        switch self {
        case .low: .red
        case .full: .green
        }
    }
}
