import Foundation

/// Picks the colour that represents an album cover, for tinting the playback
/// bars the way the iPhone tints its Dynamic Island waveform.
///
/// Works in OKLab rather than HSB: HSB's "saturation" is not comparable
/// across hues (it over-weights yellow, under-weights blue), so "is this
/// cover colourful enough to tint with?" has no honest answer in it.
enum AlbumColor {
    /// Below this chroma the cover is effectively greyscale and gets no tint
    /// at all — a muddy grey reads as a bug, not a design. Measured against a
    /// black-and-white cover, which scores 0.017.
    static let chromaFloor = 0.045
    /// Bars sit on pure black, so lightness is raised to here regardless of
    /// how dark the cover is. Hue and chroma survive; legibility is not
    /// left to chance.
    static let minimumLightness = 0.78
    private static let clusterCount = 5
    private static let iterations = 12

    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// `pixels` is tightly packed RGBA8.
    static func from(pixels: [UInt8], width: Int, height: Int) -> RGB? {
        let count = width * height
        guard count > 0, pixels.count >= count * 4 else { return nil }

        var samples: [Lab] = []
        samples.reserveCapacity(count)
        for index in 0 ..< count {
            let offset = index * 4
            guard pixels[offset + 3] > 0 else { continue }
            samples.append(
                Lab(
                    srgb: Double(pixels[offset]) / 255,
                    Double(pixels[offset + 1]) / 255,
                    Double(pixels[offset + 2]) / 255
                )
            )
        }
        guard !samples.isEmpty else { return nil }

        let clusters = cluster(samples)
        guard
            let best = clusters
            .map({ (lab: $0.center, score: $0.center.chroma * (Double($0.count) / Double(samples.count)).squareRoot())
            })
            .max(by: { $0.score < $1.score })?.lab,
            best.chroma >= chromaFloor
        else {
            return nil
        }
        return Lab(
            lightness: max(best.lightness, minimumLightness),
            greenRed: best.greenRed,
            blueYellow: best.blueYellow
        ).rgb
    }

    // MARK: - k-means

    /// Seeded deterministically. Random seeding would give the same album a
    /// different colour on every launch, which reads as a glitch.
    private static func cluster(_ samples: [Lab]) -> [(center: Lab, count: Int)] {
        var centers = seeds(samples)
        var assignment = [Int](repeating: 0, count: samples.count)

        for _ in 0 ..< iterations {
            for (index, sample) in samples.enumerated() {
                assignment[index] = nearest(sample, in: centers)
            }
            var sums = [Lab](repeating: Lab(lightness: 0, greenRed: 0, blueYellow: 0), count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for (index, sample) in samples.enumerated() {
                let slot = assignment[index]
                sums[slot] = sums[slot].adding(sample)
                counts[slot] += 1
            }
            for slot in centers.indices where counts[slot] > 0 {
                centers[slot] = sums[slot].divided(by: Double(counts[slot]))
            }
        }

        var counts = [Int](repeating: 0, count: centers.count)
        for sample in samples {
            counts[nearest(sample, in: centers)] += 1
        }
        return zip(centers, counts).filter { $0.1 > 0 }.map { (center: $0.0, count: $0.1) }
    }

    /// k-means++ style: first sample, then repeatedly the sample furthest
    /// from everything chosen so far. No RNG, so the result is reproducible.
    private static func seeds(_ samples: [Lab]) -> [Lab] {
        var chosen = [samples[0]]
        while chosen.count < min(clusterCount, samples.count) {
            var furthest = samples[0]
            var furthestDistance = -1.0
            for sample in samples {
                let distance = chosen.map { $0.distanceSquared(to: sample) }.min() ?? 0
                if distance > furthestDistance {
                    furthestDistance = distance
                    furthest = sample
                }
            }
            chosen.append(furthest)
        }
        return chosen
    }

    private static func nearest(_ sample: Lab, in centers: [Lab]) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, center) in centers.enumerated() {
            let distance = center.distanceSquared(to: sample)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

/// Minimal OKLab, per Björn Ottosson's published matrices.
private struct Lab {
    let lightness: Double
    /// OKLab's `a` axis: green at negative, red at positive.
    let greenRed: Double
    /// OKLab's `b` axis: blue at negative, yellow at positive.
    let blueYellow: Double

    var chroma: Double {
        (greenRed * greenRed + blueYellow * blueYellow).squareRoot()
    }

    init(lightness: Double, greenRed: Double, blueYellow: Double) {
        self.lightness = lightness
        self.greenRed = greenRed
        self.blueYellow = blueYellow
    }

    init(srgb red: Double, _ green: Double, _ blue: Double) {
        let linearRed = Lab.linear(red)
        let linearGreen = Lab.linear(green)
        let linearBlue = Lab.linear(blue)
        // Cone responses, cube-rooted — the long/medium/short of LMS.
        let long = cbrt(0.4122214708 * linearRed + 0.5363325363 * linearGreen + 0.0514459929 * linearBlue)
        let medium = cbrt(0.2119034982 * linearRed + 0.6806995451 * linearGreen + 0.1073969566 * linearBlue)
        let short = cbrt(0.0883024619 * linearRed + 0.2817188376 * linearGreen + 0.6299787005 * linearBlue)
        lightness = 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short
        greenRed = 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short
        blueYellow = 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
    }

    var rgb: AlbumColor.RGB {
        let long = pow(lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow, 3)
        let medium = pow(lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow, 3)
        let short = pow(lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow, 3)
        return AlbumColor.RGB(
            red: Lab.encode(4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short),
            green: Lab.encode(-1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short),
            blue: Lab.encode(-0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short)
        )
    }

    func adding(_ other: Lab) -> Lab {
        Lab(
            lightness: lightness + other.lightness,
            greenRed: greenRed + other.greenRed,
            blueYellow: blueYellow + other.blueYellow
        )
    }

    func divided(by divisor: Double) -> Lab {
        Lab(lightness: lightness / divisor, greenRed: greenRed / divisor, blueYellow: blueYellow / divisor)
    }

    func distanceSquared(to other: Lab) -> Double {
        let deltaL = lightness - other.lightness
        let deltaA = greenRed - other.greenRed
        let deltaB = blueYellow - other.blueYellow
        return deltaL * deltaL + deltaA * deltaA + deltaB * deltaB
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ channel: Double) -> Double {
        let clamped = min(max(channel, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
