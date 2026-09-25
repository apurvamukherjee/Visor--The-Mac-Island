import AppKit
import SwiftUI

/// A record turning in place of the album art.
///
/// Backed by `CALayer`: a continuous SwiftUI rotation re-runs the view graph
/// every frame. Here the whole disc is drawn once into layers and the render
/// server spins it, so the main thread does nothing between track changes.
///
/// The spin is *removed*, not paused, whenever the island isn't showing it —
/// collapse, pause, or Reduce Motion. An animation left attached to an
/// offscreen layer still keeps the render server awake.
///
/// Ported from Visor 2.x into the player's album-art slot. It fills whatever
/// square the slot gives it (the caller fixes the aspect ratio), so switching
/// vinyl on moves nothing around it.
struct VinylDisc: NSViewRepresentable {
    var isSpinning: Bool
    /// The album colour, used for the centre label.
    var tint: NSColor
    /// Drawn in the label when there's art to show — a real record's centre.
    var artwork: CGImage?

    func makeNSView(context _: Context) -> VinylDiscView {
        VinylDiscView()
    }

    func updateNSView(_ view: VinylDiscView, context: Context) {
        view.configure(tint: tint, artwork: artwork)
        view.setSpinning(isSpinning && !context.environment.accessibilityReduceMotion)
    }
}

@MainActor
final class VinylDiscView: NSView {
    private let disc = CALayer()
    private let label = CAShapeLayer()
    private let labelArt = CALayer()
    private let sheen = CAGradientLayer()
    private let arm = CAShapeLayer()
    /// The arm's mount. Its own layer because it must not turn with the arm.
    private let armPivot = CALayer()
    /// Children of `arm`, so they swing with it.
    private let headshell = CALayer()
    private let counterweight = CALayer()
    private var isSpinning = false

    /// One turn every 8 seconds — slower than a real 33⅓ record, which at
    /// this size reads as frantic rather than calm.
    private static let secondsPerTurn = 8.0
    private static let rotationKey = "spin"
    /// Parked on the arm rest, swung clear of the platter.
    private static let armRestAngle = 30.0
    /// Down in the lead-in groove at the record's outer edge — where a real
    /// arm starts a side, not over the middle of the disc.
    private static let armPlayAngle = 3.0
    /// A real cueing lever lowers the arm slowly and deliberately.
    private static let armSwingDuration = 0.55
    /// Headshell offset angle. ~22° on a typical 9" arm — the cant that puts
    /// the cartridge tangent to the groove.
    private static let offsetAngle = 22.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(disc)
        layer?.addSublayer(sheen)
        // Siblings of `disc`, not children: anything parented to the record
        // turns with it, and a tonearm that spins is a fairground ride.
        layer?.addSublayer(arm)
        layer?.addSublayer(armPivot)
        arm.addSublayer(headshell)
        arm.addSublayer(counterweight)
        disc.addSublayer(label)
        label.addSublayer(labelArt)
        labelArt.masksToBounds = true
        labelArt.contentsGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // Geometry is set without an implicit animation, or every resize
        // would animate the grooves into place.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The record gives up a little of the box so the tonearm's pivot has
        // somewhere to sit without overhanging the island's edge.
        let side = min(bounds.width, bounds.height) * 0.88
        let rect = CGRect(x: 0, y: (bounds.height - side) / 2, width: side, height: side)
        disc.frame = rect
        disc.cornerRadius = side / 2
        disc.masksToBounds = true
        drawGrooves(side: side)

        let labelSide = side * 0.38
        label.frame = CGRect(
            x: (side - labelSide) / 2,
            y: (side - labelSide) / 2,
            width: labelSide,
            height: labelSide
        )
        label.cornerRadius = labelSide / 2
        labelArt.frame = label.bounds
        labelArt.cornerRadius = labelSide / 2
        // The spindle hole, punched through the label.
        let hole = labelSide * 0.16
        let path = CGMutablePath()
        path.addEllipse(in: label.bounds)
        path.addEllipse(in: label.bounds.insetBy(dx: (labelSide - hole) / 2, dy: (labelSide - hole) / 2))
        label.path = path
        label.fillRule = .evenOdd
        CATransaction.commit()
    }

    func configure(tint: NSColor, artwork: CGImage?) {
        // The new player re-renders on every playback-position tick; only a
        // real change of colour or cover is worth a layer write.
        let currentArtwork = labelArt.contents.map { $0 as AnyObject }
        guard label.fillColor != tint.cgColor || currentArtwork !== artwork else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.fillColor = tint.cgColor
        labelArt.contents = artwork
        // Art sits under the label's punched shape, so the spindle hole still
        // reads through it.
        labelArt.opacity = artwork == nil ? 0 : 0.85
        CATransaction.commit()
    }

    /// Vinyl is black-on-black here, so the grooves are the only thing that
    /// makes the disc legible against the island. Concentric hairlines plus a
    /// single soft sheen, drawn once.
    private func drawGrooves(side: CGFloat) {
        disc.sublayers?.filter { $0 !== label }.forEach { $0.removeFromSuperlayer() }

        let base = CAGradientLayer()
        base.frame = disc.bounds
        base.type = .radial
        base.colors = [
            NSColor(white: 0.16, alpha: 1).cgColor,
            NSColor(white: 0.06, alpha: 1).cgColor
        ]
        base.startPoint = CGPoint(x: 0.5, y: 0.5)
        base.endPoint = CGPoint(x: 1, y: 1)
        disc.insertSublayer(base, at: 0)

        let grooves = CAShapeLayer()
        grooves.frame = disc.bounds
        grooves.fillColor = nil
        grooves.strokeColor = NSColor(white: 1, alpha: 0.05).cgColor
        grooves.lineWidth = 0.5
        let path = CGMutablePath()
        // Stop short of the label; grooves under it would never be seen.
        for step in stride(from: side * 0.44, to: side * 0.21, by: -(side * 0.045)) {
            path.addEllipse(in: disc.bounds.insetBy(dx: side / 2 - step, dy: side / 2 - step))
        }
        grooves.path = path
        disc.insertSublayer(grooves, above: base)

        // A fixed highlight across the disc: because it does *not* rotate with
        // the record, the spin reads as motion under a light rather than a
        // texture being dragged around.
        // Held in a property and reused: it is a sibling of `disc` rather than
        // a child (a child would rotate with the record), so `drawGrooves`'
        // cleanup of `disc.sublayers` cannot reach it — left untracked, every
        // layout pass stacked another translucent gradient on the last.
        sheen.colors = [
            NSColor.clear.cgColor,
            NSColor(white: 1, alpha: 0.10).cgColor,
            NSColor.clear.cgColor
        ]
        sheen.locations = [0.15, 0.5, 0.85]
        sheen.startPoint = CGPoint(x: 0, y: 0)
        sheen.endPoint = CGPoint(x: 1, y: 1)
        sheen.frame = disc.frame
        sheen.cornerRadius = side / 2
        sheen.masksToBounds = true

        layOutArm(side: side)
    }

    /// The tonearm: a pivot at the disc's top-right and a straight arm angling
    /// down onto the record. Drawn pointing at the rest position; `setSpinning`
    /// swings it inward over the grooves, which is the whole play/pause tell
    /// in vinyl mode — the disc alone can't say whether it is turning in a
    /// still frame.
    /// The tonearm, built the way a real one is (Fluance/Audio-Technica
    /// teardowns, Analog Planet's geometry primer): a pivot with a
    /// counterweight *behind* it balancing the arm, an S-shaped tube sweeping
    /// forward, and a headshell angled inward at the offset angle — ~22° on a
    /// typical 9" arm, which is what makes the cartridge sit tangent to the
    /// groove instead of square to the tube.
    ///
    /// The counterweight matters visually as well as mechanically: without
    /// the mass behind the pivot the arm reads as a stick glued to the deck.
    private func layOutArm(side: CGFloat) {
        // Pivot sits outside the platter's top-right, in the corner the 0.88
        // inset freed up — a real arm reaches in from beyond the record.
        let pivot = CGPoint(x: disc.frame.maxX - side * 0.03, y: disc.frame.minY + side * 0.12)
        let reach = side * 0.42
        let path = CGMutablePath()

        // Counterweight stub, behind the pivot and opposite the headshell.
        path.move(to: pivot)
        path.addLine(to: CGPoint(x: pivot.x + side * 0.055, y: pivot.y - side * 0.085))

        // The S-curve: out from the pivot, bending back toward it, then out
        // again to the headshell. Two arcs rather than one, which is what
        // distinguishes an S-arm from a J-arm.
        let elbow = CGPoint(x: pivot.x - side * 0.07, y: pivot.y + reach * 0.45)
        let tip = CGPoint(x: pivot.x - side * 0.02, y: pivot.y + reach)
        path.move(to: pivot)
        path.addCurve(
            to: elbow,
            control1: CGPoint(x: pivot.x - side * 0.005, y: pivot.y + reach * 0.16),
            control2: CGPoint(x: pivot.x - side * 0.075, y: pivot.y + reach * 0.28)
        )
        path.addCurve(
            to: tip,
            control1: CGPoint(x: pivot.x - side * 0.065, y: pivot.y + reach * 0.64),
            control2: CGPoint(x: pivot.x - side * 0.045, y: pivot.y + reach * 0.86)
        )
        arm.path = path
        arm.frame = bounds
        arm.fillColor = nil
        arm.strokeColor = NSColor(white: 0.80, alpha: 1).cgColor
        arm.lineWidth = max(1.4, side * 0.026)
        arm.lineCap = .round
        arm.lineJoin = .round
        arm.anchorPoint = CGPoint(x: pivot.x / bounds.width, y: pivot.y / bounds.height)
        arm.position = pivot

        layOutHeadshell(at: tip, side: side)
        layOutCounterweight(at: pivot, side: side)

        let dot = side * 0.085
        armPivot.frame = CGRect(x: pivot.x - dot / 2, y: pivot.y - dot / 2, width: dot, height: dot)
        armPivot.cornerRadius = dot / 2
        armPivot.backgroundColor = NSColor(white: 0.58, alpha: 1).cgColor

        arm.transform = CATransform3DMakeRotation(
            (isSpinning ? Self.armPlayAngle : Self.armRestAngle) * .pi / 180,
            0, 0, 1
        )
    }

    /// The headshell, canted by the offset angle. Drawn into the arm layer's
    /// own coordinate space so it swings with the arm.
    private func layOutHeadshell(at tip: CGPoint, side: CGFloat) {
        let width = side * 0.085
        let depth = side * 0.055
        headshell.frame = CGRect(x: tip.x - width / 2, y: tip.y - depth / 2, width: width, height: depth)
        headshell.cornerRadius = depth * 0.3
        headshell.backgroundColor = NSColor(white: 0.86, alpha: 1).cgColor
        headshell.transform = CATransform3DMakeRotation(Self.offsetAngle * .pi / 180, 0, 0, 1)
    }

    /// Mass behind the pivot. Cylindrical on a real deck, so a rounded stub
    /// rather than a disc.
    private func layOutCounterweight(at pivot: CGPoint, side: CGFloat) {
        let width = side * 0.10
        let depth = side * 0.075
        let centre = CGPoint(x: pivot.x + side * 0.065, y: pivot.y - side * 0.10)
        counterweight.frame = CGRect(
            x: centre.x - width / 2,
            y: centre.y - depth / 2,
            width: width,
            height: depth
        )
        counterweight.cornerRadius = depth * 0.4
        counterweight.backgroundColor = NSColor(white: 0.52, alpha: 1).cgColor
    }

    func setSpinning(_ spinning: Bool) {
        guard spinning != isSpinning else { return }
        isSpinning = spinning
        if spinning {
            // Resumes from wherever the last turn stopped, so a pause/play
            // doesn't snap the record back to top-dead-centre.
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = 2 * Double.pi
            animation.duration = Self.secondsPerTurn
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            disc.add(animation, forKey: Self.rotationKey)
        } else {
            disc.removeAnimation(forKey: Self.rotationKey)
        }
        swingArm(down: spinning)
    }

    /// One transform per play/pause, not a loop — it settles and then costs
    /// nothing. `CATransaction` carries the duration because the property is
    /// set directly rather than through an added animation.
    private func swingArm(down: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.armSwingDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        arm.transform = CATransform3DMakeRotation(
            (down ? Self.armPlayAngle : Self.armRestAngle) * .pi / 180,
            0, 0, 1
        )
        CATransaction.commit()
    }

    /// Nothing may keep animating once the island stops showing it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            setSpinning(false)
        }
    }
}
