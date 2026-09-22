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
    /// When the last wake/login greeting was shown, so it fires at most
    /// once a day regardless of how many times the Mac wakes. Stored as a
    /// `Date`; a build before 2026-09-22 wrote a `yyyy-MM-dd` string here,
    /// which now reads as absent and costs one extra greeting on upgrade.
    static let lastGreetingDayKey = "lastGreetingDay"
    /// Set once the three-step welcome flow has been shown or dismissed.
    static let hasSeenWelcomeKey = "hasSeenWelcome"
    /// What the greeting calls you. Empty means "use the account's name",
    /// which is what everyone who never opens Settings gets — the greeting
    /// was hardcoded to one person before this existed.
    static let userNameKey = "userName"

    /// The first word of the account's full name, falling back to the short
    /// user name. macOS already knows who this is; asking would be asking
    /// for something it could have read.
    static var defaultUserName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        if let first = full.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return NSUserName()
    }

    static func userName(in defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: userNameKey)?.trimmingCharacters(in: .whitespaces)
        guard let stored, !stored.isEmpty else { return defaultUserName }
        return stored
    }

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

    // MARK: - Hover

    /// How long the pointer has to rest on the island before it opens, in
    /// milliseconds. 120 is what Visor has always used, and is the default —
    /// so unlike the switches in `NewFeatures`, this one has a value rather
    /// than an off position, and cannot ride `bool(forKey:)`'s false.
    static let hoverIntentDelayKey = "hoverIntentDelayMilliseconds"
    /// `PaletteCommandID.rawValue` -> a one-letter key, pressed on its own
    /// inside the palette while the query is still empty.
    static let paletteShortcutsKey = "paletteShortcuts"
    /// `PaletteCommandID.rawValue` -> `LaunchGroup`, JSON-encoded. Entirely
    /// user-authored — nothing is preloaded into this key.
    static let launchGroupsKey = "launchGroups"

    // MARK: - AI usage

    /// A token target *you* set, per tool. There is no way to read the real
    /// plan limit off this machine — Anthropic and OpenAI enforce those
    /// server-side and cache nothing locally (checked) — so the badge's
    /// percentage is progress toward your own number or it is nothing at all.
    /// Unset (0) means no percentage is drawn, which is the default.
    static let claudeDailyBudgetKey = "aiUsage.claudeDailyBudget"
    static let codexDailyBudgetKey = "aiUsage.codexDailyBudget"

    static func dailyTokenBudgetKey(for tool: AIUsageTool) -> String {
        switch tool {
        case .claude: claudeDailyBudgetKey
        case .codex: codexDailyBudgetKey
        }
    }

    static func dailyTokenBudget(for tool: AIUsageTool, in defaults: UserDefaults = .standard) -> Int {
        max(defaults.integer(forKey: dailyTokenBudgetKey(for: tool)), 0)
    }

    static let hoverIntentDelayDefault = 120.0
    /// 0 is a real choice — open the instant the pointer lands — not a
    /// missing value, which is why the read below distinguishes the two.
    static let hoverIntentDelayRange: ClosedRange<Double> = 0 ... 400

    static var hoverIntentDelay: Duration {
        .milliseconds(Int(hoverIntentDelayMilliseconds(in: .standard)))
    }

    static func hoverIntentDelayMilliseconds(in defaults: UserDefaults) -> Double {
        guard let stored = defaults.object(forKey: hoverIntentDelayKey) as? Double else {
            return hoverIntentDelayDefault
        }
        return min(max(stored, hoverIntentDelayRange.lowerBound), hoverIntentDelayRange.upperBound)
    }

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
    ///
    /// Every opt-in change is appended from `NewFeatures.all` rather than
    /// listed by hand, so a new one cannot ship and then quietly survive a
    /// restore because somebody forgot this list existed.
    static let resettableKeys: [String] = ownKeys + NewFeatures.keys

    private static let ownKeys: [String] = [
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
        hoverIntentDelayKey,
        userNameKey,
        paletteShortcutsKey,
        claudeDailyBudgetKey,
        codexDailyBudgetKey,
        LockScreenSettings.liveActivityKey,
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
