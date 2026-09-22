//
//  LockScreenNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 4/14/26.
//

import SwiftUI

/// The padlock the island wears while the screen is locked. Ported from the
/// reference's `LockScreenNotchView`.
///
/// This is a *compact activity inside the island*, the way the reference has
/// it — not a separate floating panel, which is what a first pass at this
/// built and why it sat in the wrong place.
struct LockScreenNotchView: View {
    let isLocked: Bool
    let style: LockScreenStyle

    var body: some View {
        HStack {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            if style == .enlarged {
                Text(verbatim: isLocked ? "Locked" : "Unlocked")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        // The reference varied these on a `notchScale` / `isDynamicIsland`
        // environment pair that nothing ever wrote, so only this branch was
        // ever taken. Folded to the values it actually drew.
        .padding(.horizontal, 14)
    }
}
