import AppKit

/// Gesture confirmations were tried on swipes, taps and toggles and read as
/// chattery — everyday interactions stay silent. The three haptics here are
/// each a moment that happens at most a few times a day and that the user is
/// already looking at when it fires: the bar the original finding set, not a
/// lower one.
///
/// No-ops on hardware without a Force Touch trackpad, so there is nothing to
/// gate. macOS exposes no "reduce haptics" accessibility setting; the system
/// setting that does exist ("Force Click and haptic feedback") is honoured by
/// the performer itself.
enum Haptics {
    /// The island changed shape. Timed to the drawn frame so the buzz lands
    /// with the animation instead of ahead of it.
    static func shapeChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
    }

    /// The once-a-day wake/login greeting appeared.
    static func greeting() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
    }

    /// The idle-island double-click easter egg fired.
    static func wave() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
    }
}
