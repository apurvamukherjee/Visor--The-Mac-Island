import CoreGraphics
import SwiftUI

/// Which of the island's two targets a drop landed on.
///
/// Pure, and tested, because getting it backwards AirDrops somebody's file
/// to whoever is nearby instead of putting it on the shelf. That is not a
/// bug you want to find by trying it.
enum DropZone: Equatable {
    case stash
    case airDrop

    /// `location` comes from `dropDestination` in the canvas's coordinates.
    /// The canvas is wider than the island but shares its midX, so the split
    /// falls exactly where the divider is drawn.
    ///
    /// With the zones hidden the island stays one target and ⌥ is the only
    /// way to reach AirDrop — which is what has always shipped, and what
    /// this has to keep doing for anyone who never turns the zones on.
    static func resolve(
        location: CGPoint,
        canvasWidth: CGFloat,
        zonesVisible: Bool,
        optionHeld: Bool
    ) -> DropZone {
        if optionHeld {
            return .airDrop
        }
        guard zonesVisible else {
            return .stash
        }
        return location.x > canvasWidth / 2 ? .airDrop : .stash
    }
}

/// The island's two drop targets, drawn the moment a drag arrives over it.
///
/// Neither target is new — a plain drop has always stashed the file and an
/// ⌥ drop has always sent it — but the only place that was written down is
/// the README, which is where a feature goes when the UI cannot say it. The
/// halves say it instead. ⌥ keeps working, so the shortcut is a shortcut
/// rather than the only way in.
struct DropZonesView: View {
    let size: CGSize
    /// Clears the camera housing, the way every expanded layout does.
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            zone(symbol: "tray.and.arrow.down.fill", label: "Stash")
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1)
                .padding(.vertical, 8)
            zone(symbol: "airplayaudio", label: "AirDrop")
        }
        .padding(.top, topInset)
        .padding(.bottom, IslandSpacing.bottom)
        .frame(width: size.width, height: size.height)
        // Opaque, so whatever the island was showing is covered rather than
        // read through. The surface under it is black anyway; this is here
        // so the labels never have album art behind them.
        .background(.black)
    }

    private func zone(symbol: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
