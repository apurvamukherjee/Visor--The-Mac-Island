import AppKit
import SwiftUI

/// Orchestrates frame-vs-animation sequencing: grow sets the frame first
/// (invisible, transparent-into-transparent) then animates the shape;
/// shrink animates the shape first then sets the frame last. A generation
/// counter guards a stale collapse completion from yanking the frame if a
/// rapid re-hover retargets the animation mid-flight.
@MainActor
final class NotchWindowController {
    private let store: NotchStore
    private let panel: NotchPanel
    private let contentView: NotchContentView
    private var generation = 0
    private var hoverIntentTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private static let hoverIntentDelay: Duration = .milliseconds(120)

    init?(store: NotchStore) {
        guard let screen = Self.targetScreen() else { return nil }
        self.store = store
        let closedRect = NotchGeometry.closedRect(for: screen)
        panel = NotchPanel(contentRect: closedRect)
        contentView = NotchContentView(store: store, rootView: NotchRootView(store: store))
        panel.contentView = contentView
        store.setClosedSize(closedRect.size)
        repositionHostingView(for: closedRect.width)
        contentView.onMouseEntered = { [weak self] in self?.scheduleExpand() }
        contentView.onMouseExited = { [weak self] in self?.scheduleCollapse() }
    }

    func start() {
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
    }

    func stop() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        for observer in [screenObserver, sleepObserver, wakeObserver].compactMap(\.self) {
            NotificationCenter.default.removeObserver(observer)
        }
        screenObserver = nil
        sleepObserver = nil
        wakeObserver = nil
        panel.orderOut(nil)
    }

    private func scheduleExpand() {
        hoverIntentTask?.cancel()
        hoverIntentTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverIntentDelay)
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    private func scheduleCollapse() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        collapse()
    }

    private func expand() {
        guard let screen = Self.targetScreen() else { return }
        generation += 1
        let expandedRect = NotchGeometry.expandedRect(for: screen)
        panel.setFrame(expandedRect, display: true)
        repositionHostingView(for: expandedRect.width)
        withAnimation(Motion.resolved(Motion.open)) {
            store.setState(.expanded)
        }
    }

    private func collapse() {
        generation += 1
        let gen = generation
        withAnimation(
            Motion.resolved(Motion.close),
            completionCriteria: .logicallyComplete
        ) {
            store.setState(.closed)
        } completion: { [weak self] in
            guard let self, gen == generation else { return }
            finishCollapse()
        }
    }

    private func finishCollapse() {
        guard let screen = Self.targetScreen() else { return }
        let closedRect = NotchGeometry.closedRect(for: screen)
        panel.setFrame(closedRect, display: true)
        store.setClosedSize(closedRect.size)
        repositionHostingView(for: closedRect.width)
    }

    /// Shared by screen-parameter changes, sleep, and wake: cancel any
    /// pending hover intent, snap closed with no animation, resync geometry.
    private func handleScreenChange() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        generation += 1
        store.setState(.closed)
        guard let screen = Self.targetScreen() else { return }
        let closedRect = NotchGeometry.closedRect(for: screen)
        panel.setFrame(closedRect, display: true)
        store.setClosedSize(closedRect.size)
        repositionHostingView(for: closedRect.width)
    }

    private func repositionHostingView(for frameWidth: CGFloat) {
        contentView.hostingView.frame.origin = CGPoint(
            x: (frameWidth - NotchGeometry.expandedSize.width) / 2,
            y: 0
        )
    }

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main
    }
}
