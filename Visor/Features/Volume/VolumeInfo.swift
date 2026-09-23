/// The system output volume as the island shows it.
struct VolumeInfo: Equatable, Sendable {
    /// 0...1 on the default output device's main channel.
    var level: Float
    var isMuted: Bool

    /// Muting leaves the hardware level where it was, so the two are stored
    /// apart and folded only here — unmuting has to restore what was set.
    var effectiveLevel: Float {
        isMuted ? 0 : level
    }

    var percentage: Int {
        Int((effectiveLevel * 100).rounded())
    }

    static func clamped(_ level: Float) -> Float {
        level.clamped(to: 0 ... 1)
    }
}

enum VolumeGlyph {
    /// The same three tiers Control Center draws, so the island and the
    /// system HUD never disagree about how loud "loud" looks.
    static func symbolName(level: Float, isMuted: Bool) -> String {
        if isMuted {
            return "speaker.slash.fill"
        }
        return switch level {
        case ..<0.001: "speaker.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
