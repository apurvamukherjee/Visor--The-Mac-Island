import AppKit
import CoreImage
import ImageIO
import SwiftUI

/// Decodes and downsamples at most once per track identity (RESEARCH.md
/// §5.2.7). Artwork can arrive in a later push than the track metadata
/// (the adapter's own `preservingArtworkIfDowngrade` confirms this), so a
/// nil `source` doesn't get cached as final — only a successful decode does.
@MainActor
final class ArtworkCache {
    private var identity: String?
    private var cached: CGImage?
    private var cachedTint: Color?
    private var cachedBleed: CGImage?

    /// Shared across tracks: building a `CIContext` per blur is the expensive
    /// part, not the blur itself.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func image(for identity: String, source: NSImage?) -> CGImage? {
        if identity != self.identity {
            self.identity = identity
            cached = nil
            cachedTint = nil
            cachedBleed = nil
        }
        if cached == nil, let source {
            cached = Self.downsample(source, maxPixels: 96)
            cachedTint = cached.flatMap(Self.tint)
            cachedBleed = cached.flatMap(Self.bleed)
        }
        return cached
    }

    /// Valid only for the identity most recently passed to `image(for:source:)`.
    func tint(for identity: String) -> Color? {
        identity == self.identity ? cachedTint : nil
    }

    /// The pre-blurred backdrop. Blurring once here rather than with SwiftUI's
    /// `.blur()` is the whole point: a live modifier re-rasterises every time
    /// the island changes state, and the island changes state constantly.
    func bleed(for identity: String) -> CGImage? {
        identity == self.identity ? cachedBleed : nil
    }

    /// Clamped before blurring, or the filter samples transparent black past
    /// the edges and the result fades out at its own borders — which reads as
    /// a vignette sitting inside the island rather than a wash behind it.
    private static func bleed(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        guard
            let blurred = CIFilter(
                name: "CIGaussianBlur",
                parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: 18]
            )?.outputImage
        else {
            return nil
        }
        return ciContext.createCGImage(blurred, from: extent)
    }

    /// One 32x32 read per track — small enough that the clustering is
    /// trivial, large enough to find a colour that is actually in the art.
    private static func tint(_ image: CGImage) -> Color? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let rgb = AlbumColor.from(pixels: pixels, width: side, height: side) else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func downsample(_ image: NSImage, maxPixels: Int) -> CGImage? {
        guard
            let data = image.tiffRepresentation,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
