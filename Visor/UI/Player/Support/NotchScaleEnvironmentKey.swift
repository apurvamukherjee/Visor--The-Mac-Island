//
//  NotchScaleEnvironmentKey.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 2/23/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var notchScale: CGFloat = 1.0

    @Entry var isDynamicIsland: Bool = false
}
