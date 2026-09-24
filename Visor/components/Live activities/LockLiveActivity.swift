//
//  LockLiveActivity.swift
//  Visor
//

import SwiftUI

/// The padlock the closed notch wears for a few seconds when the screen
/// locks or unlocks, before it hands back to the album cover.
///
/// Laid out exactly like `MusicLiveActivity`: a square wing on each side
/// of the notch, so the hand-over changes what is in the wing, never the
/// width of the island.
struct LockLiveActivity: View {
    let isLocked: Bool
    /// The music wing's own square: the closed notch height minus 12.
    let side: CGFloat
    let centerWidth: CGFloat

    var body: some View {
        HStack {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                // Morphs the shackle rather than swapping two pictures, so
                // unlocking reads as the latch opening.
                .contentTransition(.symbolEffect(.replace))
                .frame(width: side, height: side)

            Rectangle()
                .fill(.black)
                .frame(width: centerWidth)

            Color.clear
                .frame(width: side, height: side)
        }
    }
}
