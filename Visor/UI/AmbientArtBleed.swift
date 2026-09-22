import SwiftUI

/// A soft halo of the album's colour directly behind the artwork, as if the
/// cover were lit from behind.
///
/// This started as a wash across the whole expanded panel and was cut back
/// after live feedback: at panel scale a blurred cover reads as a cheap
/// gradient smeared over the island and fights the black surface. Confined to
/// the art it does the opposite — the cover looks lit rather than pasted on,
/// and the rest of the island stays the pure black that lets it blend with
/// the real notch (RESEARCH.md §2.4b).
///
/// Two things keep it from becoming a visible rectangle again:
/// - it is masked by a radial gradient, so it fades to nothing well before
///   its own bounds rather than ending on an edge
/// - it never exceeds `opacityCeiling` over black
struct AmbientArtBleed: View {
    let image: CGImage
    /// The artwork's side. The halo is drawn larger than this and fades out
    /// inside the margin.
    let side: CGFloat

    /// How far past the artwork the glow reaches.
    private static let spread = 1.9
    /// Composited over black. Low by design: this is meant to be noticed as
    /// depth behind the cover, not as a coloured panel.
    private static let opacityCeiling = 0.55

    /// Reduce Transparency asks for exactly this kind of decoration to stop;
    /// Increase Contrast is already honoured by `PlaybackBars`, and a glow
    /// behind content is what it is about.
    static var isPermitted: Bool {
        let flags = Motion.flags
        return !flags.reduceTransparency && !flags.increaseContrast
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: side * Self.spread, height: side * Self.spread)
            .mask {
                // Solid over the cover, gone by the edge — the gradient is
                // what stops this reading as a blurred square.
                RadialGradient(
                    colors: [.white, .white.opacity(0.45), .clear],
                    center: .center,
                    startRadius: side * 0.30,
                    endRadius: side * Self.spread / 2
                )
            }
            .opacity(Self.opacityCeiling)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}
