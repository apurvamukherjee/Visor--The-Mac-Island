import SwiftUI

enum LockScreenStyle: String, CaseIterable {
    case enlarged
    case compact

    var title: LocalizedStringKey {
        switch self {
        case .enlarged:
            "settings.lockScreen.style.enlarged"
        case .compact:
            "settings.lockScreen.style.compact"
        }
    }
}
