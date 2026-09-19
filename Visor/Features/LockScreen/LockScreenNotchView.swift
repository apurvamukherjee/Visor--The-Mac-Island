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
    @Environment(\.notchScale) private var scale
    @Environment(\.isDynamicIsland) private var isDynamicIsland

    let isLocked: Bool
    let style: LockScreenStyle

    var body: some View {
        HStack {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: isDynamicIsland ? 14 : 16, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            if style == .enlarged {
                Text(verbatim: isLocked ? "Locked" : "Unlocked")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        .padding(.leading, isDynamicIsland ? 6.scaled(by: scale) : 14.scaled(by: scale))
        .padding(.trailing, isDynamicIsland ? 8.scaled(by: scale) : 14.scaled(by: scale))
    }
}
