import SwiftUI

enum LockScreenMediaPanelBackgroundStyle: String, CaseIterable {
    case animatedArtwork
    case staticArtwork
    case black

    var title: String {
        switch self {
        case .animatedArtwork:
            "Animated artwork"
        case .staticArtwork:
            "Static artwork"
        case .black:
            "Black"
        }
    }
}
