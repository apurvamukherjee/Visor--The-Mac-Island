import AppKit

/// Every haptic in the app, named by what it means rather than by pattern —
/// the same reason animations come from `Motion` and not from raw springs.
///
/// All of these no-op on hardware without a Force Touch trackpad, so there is
/// nothing to gate. macOS exposes no "reduce haptics" accessibility setting;
/// the system setting that does exist ("Force Click and haptic feedback") is
/// honoured by the performer itself.
enum Haptics {
    /// A discrete choice landed: a track changed, a gesture crossed its
    /// threshold. `.alignment` is the detent-like tick used for snapping.
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A state flipped that the user can see — play/pause, a toggle.
    static func toggle() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// The island changed shape. Timed to the drawn frame so the buzz lands
    /// with the animation instead of ahead of it.
    static func shapeChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
    }
}
