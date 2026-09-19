//
//  AnimateImage.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 2/22/26.
//

import AppKit
import Lottie
import SwiftUI

/// Plays a bundled Lottie animation. Ported from the reference as-is; the
/// only thing Visor uses it for is the cursive "Welcome" on the first
/// onboarding step (`welcome.json`: one shape layer, a gradient fill and a
/// trim path that draws the stroke on).
struct AnimateImage: NSViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .autoReverse
    var backgroundBehavior: LottieBackgroundBehavior = .pauseAndRestore

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let animationView = LottieAnimationView(name: name)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.layer?.contentsGravity = .resizeAspect
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = loopMode
        animationView.backgroundBehavior = backgroundBehavior

        container.addSubview(animationView)
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            animationView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            animationView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            animationView.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor)
        ])

        animationView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        animationView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        DispatchQueue.main.async {
            animationView.play()
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if let animationView = nsView.subviews.first as? LottieAnimationView {
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        }
    }
}
