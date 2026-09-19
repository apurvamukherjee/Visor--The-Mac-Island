import AppKit
import SwiftUI

/// Expanded, offline: says what happened, then offers the only two useful
/// responses. Deliberately not a peek — being offline is a condition the
/// user acts on, not an event that scrolls past.
struct ExpandedNetworkView: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: IslandSpacing.column) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: IslandLayout.Column.alertIcon)

            VStack(alignment: .leading, spacing: 3) {
                Text("No Internet Connection")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    // Two lines is what the island reserves; a third would
                    // be clipped by the shape rather than shown.
                    .lineLimit(2)

                HStack(spacing: 8) {
                    IslandButton(title: "OK", isProminent: false, action: onDismiss)
                    IslandButton(title: "Settings", isProminent: true, action: openNetworkSettings)
                }
                .padding(.top, IslandSpacing.block)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func openNetworkSettings() {
        // The modern pane identifier; if a future macOS renames it the call
        // simply does nothing rather than opening the wrong thing.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
        onDismiss()
    }
}

/// The island's own button. `.borderedProminent` renders a system-tinted
/// capsule that reads as a sheet control against pure black, so the two
/// styles here are drawn rather than borrowed.
struct IslandButton: View {
    let title: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 62)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isProminent ? Color.accentColor : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }
}
