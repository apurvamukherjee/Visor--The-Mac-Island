import Foundation

/// One entry in the settings sidebar.
///
/// Five panes rather than one scrolling column: the old window was 340pt wide
/// with General, Now Playing, Lock Screen, Notch, a gesture sheet and About
/// stacked behind a scrollbar, so finding a setting meant scrolling past four
/// others that had nothing to do with it.
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case nowPlaying
    case features
    case shortcuts

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .nowPlaying: "Now Playing"
        case .features: "New Features"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .nowPlaying: "music.note"
        case .features: "sparkles"
        case .shortcuts: "keyboard"
        }
    }
}
