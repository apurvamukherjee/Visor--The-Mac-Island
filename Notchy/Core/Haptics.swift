import AppKit

/// The app's only haptic. Gesture confirmations were tried on swipes, taps
/// and toggles and read as chattery — the island opening is the one moment
/// where feedback matches something the user sees change.
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
}
