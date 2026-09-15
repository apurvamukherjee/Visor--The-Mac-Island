import AppKit
import ImageIO

/// Decodes and downsamples at most once per track identity (RESEARCH.md
/// §5.2.7). Artwork can arrive in a later push than the track metadata
/// (the adapter's own `preservingArtworkIfDowngrade` confirms this), so a
/// nil `source` doesn't get cached as final — only a successful decode does.
@MainActor
final class ArtworkCache {
    private var identity: String?
    private var cached: CGImage?

    func image(for identity: String, source: NSImage?) -> CGImage? {
        if identity != self.identity {
            self.identity = identity
            cached = nil
        }
        if cached == nil, let source {
            cached = Self.downsample(source, maxPixels: 96)
        }
        return cached
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
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
