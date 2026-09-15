import AppKit
import SwiftUI

/// Idle compact indicator, shown whenever the notch has a live activity
/// (charging peek or Now Playing) but isn't hovered. Deliberately content
/// -agnostic about which activity triggered it: album art on the left wing
/// while something's actually playing, battery reading always on the right
/// wing. Controls/artist text live only in the expanded (hover) view.
struct CompactActivityView: View {
    let store: NotchStore

    @State private var chargeBounce = 0

    var body: some View {
        HStack {
            if let shot = store.screenshot {
                ScreenshotChip(shot: shot, height: 18) { open(shot) }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else {
                if let artwork = store.nowPlayingArtwork {
                    Image(decorative: artwork, scale: 1)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if let info = store.nowPlaying {
                    PlaybackBars(isPlaying: info.isPlaying, height: 11, tint: store.nowPlayingTint)
                }
            }
            Spacer(minLength: 0)
            if let battery = store.battery {
                batteryGlyph(battery)
            }
        }
        .foregroundStyle(.white)
        .animation(Motion.resolved(Motion.catchIn), value: store.screenshot)
        // NotchShape's bottom corners round away with radius compactBottomRadius —
        // at x=0/width exactly, the shape's fill stops short of the full height,
        // so edge-flush content pokes outside it. Inset past the curve to stay
        // inside the fill at any vertical position.
        .padding(.horizontal, NotchShape.compactBottomRadius + 2)
    }

    private func open(_ shot: ScreenshotCatch) {
        NSWorkspace.shared.open(shot.url)
        store.setScreenshot(nil)
    }

    private func bounceIfCharging(_ info: BatteryInfo) {
        guard info.isCharging else { return }
        chargeBounce += 1
    }

    private func batteryGlyph(_ info: BatteryInfo) -> some View {
        HStack(spacing: 3) {
            Image(systemName: info.isCharging ? "bolt.fill" : "battery.100")
                .foregroundStyle(info.isCharging ? .yellow : .white)
                .contentTransition(.symbolEffect(.replace))
                // One bounce when the charger goes in. `value:` alone misses
                // it, because the peek creates this view and flips the flag in
                // the same pass — the onAppear covers that case.
                .symbolEffect(.bounce, value: chargeBounce)
                .onAppear { bounceIfCharging(info) }
                .onChange(of: info.isCharging) { _, _ in bounceIfCharging(info) }
            Text("\(info.percentage)%")
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                // Digits roll rather than pop when the charge moves.
                .contentTransition(.numericText(value: Double(info.percentage)))
                .animation(Motion.resolved(Motion.textSwap), value: info.percentage)
        }
    }
}
