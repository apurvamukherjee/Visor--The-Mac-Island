import SwiftUI

/// What colour the scrub bar's filled portion takes.
enum ProgressTintStyle: String, CaseIterable, Sendable {
    /// Plain white, as it always was.
    case standard
    /// The album's own colour, via the existing `AlbumColor` pipeline.
    case artwork
    /// The system accent the user picked in System Settings.
    case accent

    var title: String {
        switch self {
        case .standard: "Standard"
        case .artwork: "Album colour"
        case .accent: "Accent colour"
        }
    }

    /// `tint` is whatever `AlbumColor` derived for the current track; it is
    /// nil before the artwork has been decoded, and the bar falls back to
    /// white rather than flashing a different colour for one frame.
    func resolved(tint: Color?) -> Color {
        switch self {
        case .standard: .white.opacity(0.85)
        case .artwork: tint ?? .white.opacity(0.85)
        case .accent: .accentColor
        }
    }

    static var current: ProgressTintStyle {
        ProgressTintStyle(
            rawValue: UserDefaults.standard.string(forKey: Preferences.progressTintKey) ?? ""
        ) ?? .standard
    }
}
