import SwiftUI

enum LockScreenWidgetAppearanceStyle: String, CaseIterable {
    case ultraThinMaterial
    case ultraThickMaterial
    case liquidGlass

    static var availableOptions: [Self] {
        Array(allCases)
    }

    var title: String {
        switch self {
        case .ultraThinMaterial:
            "Soft"
        case .ultraThickMaterial:
            "Solid"
        case .liquidGlass:
            "Liquid glass"
        }
    }

    var isSupportedOnCurrentSystem: Bool {
        true
    }
}
