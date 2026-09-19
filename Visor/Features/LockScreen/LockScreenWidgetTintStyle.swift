import SwiftUI

enum LockScreenWidgetTintStyle: String, CaseIterable {
    case neutral
    case accent

    var title: String {
        switch self {
        case .neutral:
            "Neutral"
        case .accent:
            "Accent"
        }
    }

    func resolvedColor() -> Color? {
        switch self {
        case .neutral:
            nil
        case .accent:
            .accentColor
        }
    }
}
