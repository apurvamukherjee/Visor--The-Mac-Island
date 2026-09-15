import AppKit
import SwiftUI

/// `.hudWindow` over `.underWindowBackground`: the latter is semantically
/// "the material shown *under* a window's background" and reads washed out
/// when floated as the top surface. `.hudWindow` is the match for a small
/// translucent panel over arbitrary content, which is what the island is.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
