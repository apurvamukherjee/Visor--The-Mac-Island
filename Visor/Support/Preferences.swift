import Foundation

/// User-facing switches that outlive a launch. `UserDefaults` directly —
/// there is one of these, and a settings layer for one boolean would be a
/// layer for its own sake.
enum Preferences {
    /// Show a turning record instead of the album cover. Off by default:
    /// the cover is the honest representation of what's playing, and the
    /// record is a preference, not a fallback.
    static let vinylModeKey = "vinylMode"
    /// `MotionPreset.rawValue`. One knob drives every spring in `Motion`.
    static let motionPresetKey = "motionPreset"
    /// `yyyy-MM-dd` of the last wake/login greeting shown, so it fires at
    /// most once a day regardless of how many times the Mac wakes.
    static let lastGreetingDayKey = "lastGreetingDay"
    /// Set once the three-step welcome flow has been shown or dismissed.
    static let hasSeenWelcomeKey = "hasSeenWelcome"

    // MARK: - Notch customization

    /// Outline around the island. Off by default: the island is a solid
    /// black shape against a black cutout, and a stroke is what makes it
    /// stop being invisible when closed.
    static let strokeEnabledKey = "notchStroke"
    static let strokeWidthKey = "notchStrokeWidth"
    static let strokeOpacityKey = "notchStrokeOpacity"
    /// Points added to the measured cutout, ±. A trim, not a size: the
    /// cutout is still what everything is measured from.
    static let notchWidthOffsetKey = "notchWidthOffset"
    static let notchHeightOffsetKey = "notchHeightOffset"
    static let hidesInFullscreenKey = "hidesInFullscreen"
    /// `NotchScreenChoice.rawValue`.
    static let screenChoiceKey = "notchScreen"
    /// Tint style for the Now Playing progress bar.
    static let progressTintKey = "nowPlayingProgressTint"
    /// Show the (decorative) equaliser beside the artwork.
    static let equalizerKey = "nowPlayingEqualizer"

    static var hidesInFullscreen: Bool {
        UserDefaults.standard.bool(forKey: hidesInFullscreenKey)
    }

    /// How far the width/height trims may run, matching the reference's own
    /// ranges. Wide enough to correct a cutout macOS measures a point or two
    /// off; narrow enough that the island cannot be dragged off the notch.
    static let notchWidthOffsetRange: ClosedRange<Double> = -16 ... 16
    static let notchHeightOffsetRange: ClosedRange<Double> = -4 ... 4

    /// Every key "Restore defaults" clears. Removing a key rather than
    /// writing a default back is what keeps this honest: each accessor
    /// already states its own default, so a second table of defaults here
    /// would be one more thing to drift out of sync.
    ///
    /// `hasSeenWelcomeKey` and `lastGreetingDayKey` are deliberately absent.
    /// Neither is a setting — clearing them would replay the onboarding flow
    /// and re-fire today's greeting, which is not what "restore defaults"
    /// means to anyone pressing it.
    static let resettableKeys: [String] = [
        vinylModeKey,
        motionPresetKey,
        strokeEnabledKey,
        strokeWidthKey,
        strokeOpacityKey,
        notchWidthOffsetKey,
        notchHeightOffsetKey,
        hidesInFullscreenKey,
        screenChoiceKey,
        progressTintKey,
        equalizerKey,
        LockScreenSettings.liveActivityKey,
        LockScreenSettings.soundKey,
        LockScreenSettings.customSoundPathKey,
        LockScreenSettings.customLockSoundPathKey,
        LockScreenSettings.customUnlockSoundPathKey,
        LockScreenSettings.styleKey
    ]

    /// Clears every resettable key. Launch-at-login is *not* touched: it is a
    /// macOS login item, not a default of ours, and silently unregistering it
    /// is a surprise rather than a restore.
    static func restoreDefaults(in defaults: UserDefaults = .standard) {
        resettableKeys.forEach(defaults.removeObject(forKey:))
    }
}

/// Which display the island lives on.
enum NotchScreenChoice: String, CaseIterable, Sendable {
    /// Whichever screen actually has a cutout, else the main one. What Visor
    /// has always done, and right on every single-display Mac.
    case automatic
    case builtIn
    case main

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .builtIn: "Built-in display"
        case .main: "Main display"
        }
    }

    static var current: NotchScreenChoice {
        NotchScreenChoice(
            rawValue: UserDefaults.standard.string(forKey: Preferences.screenChoiceKey) ?? ""
        ) ?? .automatic
    }
}
