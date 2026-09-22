import AppKit
import SwiftUI

/// The compact wing's one text style, and — just as important — how wide it
/// needs to be.
///
/// The width has to be knowable *before* the island lays out, because the
/// island is sized first and filled second. Without it the text simply runs
/// across the camera housing and the middle of the sentence is not there.
/// Measured 2026-09-23, against the real font: "Good afternoon, Apurva"
/// wants 130pt and the wing offered 64.
///
/// Measured once per value rather than per layout read — `Greeting` takes
/// its width at init, and `store.layout` is read on every animation frame.
enum CompactLabel {
    static let glyphSize: CGFloat = 11
    static let spacing: CGFloat = 4

    /// Padding `CompactActivityView` puts either side of the whole row, plus
    /// a little clearance so the last letter is not flush against the
    /// cutout's edge.
    static let margin: CGFloat = NotchRadii.compact.bottom + 2 + 6

    /// Long enough for "Good afternoon," and a real first name; past this the
    /// label truncates rather than growing the island without end. A wing is
    /// sized from this in `IslandLayout.all`, so raising it widens the canvas
    /// every layout is measured against.
    static let maxWidth: CGFloat = 150

    /// `.caption2` with a rounded design — what `CompactActivityView.label`
    /// draws. Resolved once: each `NSFont` lookup is not free and this is
    /// asked on every new greeting and alert.
    ///
    /// `nonisolated(unsafe)` because `NSFont` is not marked `Sendable`. It is
    /// immutable once created and measurement goes through Core Text, which
    /// is thread-safe — but the compiler cannot know either, and pinning this
    /// to the main actor would isolate `Greeting.init` with it.
    nonisolated(unsafe) static let font: NSFont = {
        let base = NSFont.preferredFont(forTextStyle: .caption2)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }()

    /// Glyph, gap and text, clamped to `maxWidth`.
    static func width(_ text: String) -> CGFloat {
        let text = (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        return min(glyphSize + spacing + text, maxWidth)
    }
}
