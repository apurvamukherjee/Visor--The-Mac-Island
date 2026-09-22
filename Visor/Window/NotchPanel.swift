import AppKit

@MainActor
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // NSPanel defaults this to true, unlike NSWindow. In an accessory app
        // that is never frontmost, it hides the island whenever the active
        // app changes — which is what a Space switch does, so the island read
        // as "stuck on desktop 1" when it was really hidden on desktop 2.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// `NSHostingView` claims right-clicks, smart-magnify and double-clicks
    /// before they can
    /// reach `NotchContentView`'s overrides, so they are intercepted here —
    /// ahead of dispatch — rather than waiting for the responder chain that
    /// never bubbles them back up. Scroll still goes the normal route: SwiftUI
    /// declines it, so the content view sees it.
    override func sendEvent(_ event: NSEvent) {
        let intercepts = event.type == .rightMouseUp
            || event.type == .smartMagnify
            || (event.type == .leftMouseUp && event.clickCount == 2)
        if intercepts, let view = contentView as? NotchContentView, view.handleInterceptedEvent(event) {
            return
        }
        super.sendEvent(event)
    }

    /// Off except while the command palette is open. A panel that could
    /// always become key would take the keyboard away from whatever the user
    /// was typing in every time they brushed the notch — measured on a
    /// throwaway probe: a `.nonactivatingPanel` that overrides this *does*
    /// take first responder, and does it without changing the frontmost
    /// app, which is exactly what the palette needs and exactly what the
    /// rest of the island must not do.
    var acceptsKeyboard = false

    override var canBecomeKey: Bool {
        acceptsKeyboard
    }

    override var canBecomeMain: Bool {
        false
    }
}
