import AppKit

/// Everything the controller watches on the store.
///
/// Split from the controller for length. Every one of these follows the same
/// shape — read a property, re-arm on change, act — because
/// `withObservationTracking` is one-shot: a handler that forgets to register
/// again is simply never called a second time, which is why the re-arm is the
/// first line of each.
@MainActor
extension NotchWindowController {
    func registerActivityObservation() {
        withObservationTracking {
            _ = store.currentActivity
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleActivityChange() }
        }
    }

    /// The welcome flow force-opens the island itself rather than waiting
    /// for a hover, and holds it open until it finishes — see
    /// `collapseFromExpanded`'s guard below.
    func registerOnboardingObservation() {
        withObservationTracking {
            _ = store.isOnboardingActive
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleOnboardingChange() }
        }
    }

    func handleOnboardingChange() {
        registerOnboardingObservation()
        if store.isOnboardingActive {
            hoverIntentTask?.cancel()
            hoverIntentTask = nil
            guard store.state != .expanded else { return }
            expand()
        } else if !isHovering {
            collapseFromExpanded()
        }
    }

    /// The palette is the only thing in Visor that wants the keyboard, so
    /// the panel's `canBecomeKey` follows it exactly rather than being on
    /// all the time.
    func registerPaletteObservation() {
        withObservationTracking {
            _ = store.isPaletteOpen
        } onChange: { [weak self] in
            Task { @MainActor in self?.handlePaletteChange() }
        }
    }

    /// Settings moving a size trim re-measures the island in place, so the
    /// sliders can be dialled in against the real notch.
    func registerNotchSizeObservation() {
        withObservationTracking {
            _ = store.notchSizeTick
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleNotchSizeChange() }
        }
    }

    func handleNotchSizeChange() {
        registerNotchSizeObservation()
        guard let screen = Self.targetScreen() else { return }
        let closedRect = NotchGeometry.closedRect(for: screen)
        store.closedSize = closedRect.size
        // Only the resting frame is re-asserted; the state is left alone, so
        // a peek showing while the slider moves is not snapped shut.
        guard store.state == .closed else { return }
        panel.setFrame(closedRect, display: true)
        repositionHostingView(for: closedRect.width)
    }

    /// A drag heading for the notch should be met, not waited out — the
    /// island opens the moment it becomes a drop target and closes again when
    /// the drag leaves or lands.
    func registerDropObservation() {
        withObservationTracking {
            _ = store.isDropTargeted
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleDropTargetChange() }
        }
    }

    func handleDropTargetChange() {
        registerDropObservation()
        guard !isDisplayAsleep else { return }
        if store.isDropTargeted {
            hoverIntentTask?.cancel()
            hoverIntentTask = nil
            guard store.state != .expanded else { return }
            expand()
        } else if !isHovering, store.state == .expanded {
            collapseFromExpanded()
        }
    }

    func handleActivityChange() {
        registerActivityObservation()
        guard !isHovering, !isDisplayAsleep, store.state != .expanded else { return }
        switch (store.state, store.currentActivity != nil) {
        case (.closed, true): enterCompact()
        case (.compact, false): exitCompact()
        default: break
        }
    }

    /// Hiding orders the panel away; the palette's hot key is global, so
    /// ⌃⌥K is still the way back — which is the only reason hiding the
    /// island is not a trap.
    func registerHiddenObservation() {
        withObservationTracking {
            _ = store.isIslandHidden
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleHiddenChange() }
        }
    }

    func handleHiddenChange() {
        registerHiddenObservation()
        guard store.isIslandHidden else {
            panel.orderFrontRegardless()
            SkyLightPin.pin(panel)
            return
        }
        guard !store.isPaletteOpen else { return }
        panel.orderOut(nil)
    }

    func handlePaletteChange() {
        registerPaletteObservation()
        guard store.isPaletteOpen else {
            panel.acceptsKeyboard = false
            // Hands the keyboard back to whatever the user was typing in.
            // The frontmost app never changed — measured on a probe — so
            // this is giving up key status, not switching apps.
            NSApp.deactivate()
            if !isHovering {
                collapseFromExpanded()
            }
            // Closing the palette on a hidden island puts it away again,
            // rather than leaving the thing the user hid on screen.
            if store.isIslandHidden {
                panel.orderOut(nil)
            }
            return
        }
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        // The palette has to be visible even when the island is hidden —
        // otherwise the only way back from hiding it would be to relaunch.
        panel.orderFrontRegardless()
        SkyLightPin.pin(panel)
        panel.acceptsKeyboard = true
        expand()
        panel.makeKey()
        panel.makeFirstResponder(contentView)
    }
}
