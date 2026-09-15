import SwiftUI

/// Idle compact indicator, shown whenever the notch has a live activity
/// (charging peek or Now Playing) but isn't hovered. Deliberately content
/// -agnostic about which activity triggered it: album art on the left wing
/// while something's actually playing, battery reading always on the right
/// wing. Controls/artist text live only in the expanded (hover) view.
struct CompactActivityView: View {
    let store: NotchStore

    var body: some View {
        HStack {
            if let artwork = store.nowPlayingArtwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer(minLength: 0)
            if let battery = store.battery {
                batteryGlyph(battery)
            }
        }
        .foregroundStyle(.white)
    }

    private func batteryGlyph(_ info: BatteryInfo) -> some View {
        HStack(spacing: 3) {
            Image(systemName: info.isCharging ? "bolt.fill" : "battery.100")
                .foregroundStyle(info.isCharging ? .yellow : .white)
            Text("\(info.percentage)%")
                .font(.system(.caption2, design: .rounded).monospacedDigit())
        }
    }
}
