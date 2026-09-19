import SwiftUI

/// A Bluetooth device coming or going. An event, not a condition — unlike
/// the offline alert, which stays up as long as it is true.
struct BluetoothAlert: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case connected
        case disconnected
    }

    let kind: Kind
    let deviceName: String
    /// Whatever `DeviceBatteryService` already knows about this accessory, or
    /// nil. Not fetched here: the reference fused five sources for this
    /// number (a private plist, `system_profiler`, `pmset`, a GATT read and
    /// a 3s poll), and Visor already reads the one that needs no permission.
    let percentage: Int?

    /// Reuses the accessory glyph table rather than carrying its own: the
    /// device strings come from the same registry.
    var symbolName: String {
        DeviceBatteryGlyph.symbolName(for: deviceName)
    }

    var title: String {
        switch kind {
        case .connected: deviceName
        case .disconnected: deviceName
        }
    }

    var detail: String {
        switch kind {
        case .connected: percentage.map { "Connected · \($0)%" } ?? "Connected"
        case .disconnected: "Disconnected"
        }
    }

    var tint: Color {
        kind == .connected ? .white : .secondary
    }
}
