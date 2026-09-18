import AppKit
import SwiftUI

/// Idle compact indicator, shown whenever the notch has a live activity
/// (screenshot catch, wave, charging peek, Now Playing, or the daily
/// greeting) but isn't hovered. Deliberately content-agnostic about which
/// activity triggered it: the left wing shows whichever won
/// `resolveCurrentActivity`, battery reading always on the right wing.
/// Controls/artist text live only in the expanded (hover) view.
struct CompactActivityView: View {
    let store: NotchStore

    @State private var waveBounce = 0

    var body: some View {
        HStack {
            if let shot = store.screenshot {
                ScreenshotChip(
                    shot: shot,
                    height: 18,
                    onOpen: { open(shot) },
                    onDismiss: { store.setScreenshot(nil) },
                    onDropCompleted: { store.dismissScreenshot(shot) }
                )
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else if store.wave {
                Image(systemName: "hand.wave.fill")
                    .symbolEffect(.bounce, value: waveBounce)
                    .onAppear {
                        if !Motion.reduceMotion {
                            waveBounce += 1
                        }
                    }
            } else if let greeting = store.greetingText {
                Image(systemName: greeting.symbolName)
                Text(greeting.message)
                    .font(.system(.caption2, design: .rounded))
                    .lineLimit(1)
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

    private func batteryGlyph(_ info: BatteryInfo) -> some View {
        HStack(spacing: 3) {
            Image(systemName: BatteryGlyph.symbolName(percentage: info.percentage, isCharging: info.isCharging))
                .foregroundStyle(BatteryGlyph.tint(percentage: info.percentage, isCharging: info.isCharging))
                .contentTransition(.symbolEffect(.replace))
                // Driven by `BatteryService`'s own tick rather than this
                // view's mount/onChange timing: the glyph can also appear
                // because of an unrelated compact peek (screenshot, wave,
                // greeting), and that must never borrow a charge bounce it
                // didn't earn.
                .symbolEffect(.bounce, value: store.batteryBounceTick)
            Text("\(info.percentage)%")
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                // Digits roll rather than pop when the charge moves.
                .contentTransition(.numericText(value: Double(info.percentage)))
                .animation(Motion.resolved(Motion.textSwap), value: info.percentage)
        }
    }
}
