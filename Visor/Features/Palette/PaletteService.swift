import AppKit
import Carbon.HIToolbox

/// The command palette's hotkey.
///
/// `RegisterEventHotKey` and **not** a `CGEventTap`: the tap sees every
/// keystroke on the machine and needs Accessibility for it, which is the
/// permission the media-key HUD was cut to avoid. Carbon registers one
/// combination with the window server and is handed only that one.
///
/// Measured before this was written, on an ad-hoc-signed `LSUIElement`
/// bundle launched through LaunchServices so it carried its own TCC
/// identity rather than the terminal's: `AXIsProcessTrusted() == false`,
/// `RegisterEventHotKey` returned `noErr`, and no prompt appeared.
@MainActor
final class PaletteService: NotchService {
    private let store: NotchStore
    private let showSettings: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?
    private let system = SystemCommands()

    /// ⌃⌥K. Avoids ⌘ and ⇧ entirely: those are where app shortcuts live,
    /// and a palette that steals one is worse than no palette.
    private static let keyCode = UInt32(kVK_ANSI_K)
    private static let modifiers = UInt32(controlKey | optionKey)
    private static let signature = OSType(0x5653_5231)

    init(store: NotchStore, showSettings: @escaping () -> Void) {
        self.store = store
        self.showSettings = showSettings
    }

    func start() {
        store.paletteCommands = NotchStore.PaletteCommands(
            run: { [weak self] id in self?.run(id) }
        )
        // The registration follows the setting rather than the launch, so
        // turning the palette off gives the combination back to whatever
        // else wanted it. `didChangeNotification` is an observer, not a
        // poll — it fires when something writes a default, which Visor does
        // only when the user moves a control.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncRegistration() }
        }
        syncRegistration()
    }

    func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        unregister()
        system.stop()
        store.paletteCommands = nil
        store.closePalette()
    }

    private func syncRegistration() {
        let wanted = NewFeatures.commandPalette.isEnabled()
        guard wanted != (hotKey != nil) else { return }
        if wanted {
            register()
        } else {
            unregister()
            store.closePalette()
        }
    }

    private func register() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // `self` travels as the handler's user data rather than through a
        // global: the callback is a C function pointer and cannot capture.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let service = Unmanaged<PaletteService>.fromOpaque(context).takeUnretainedValue()
                // Carbon dispatches application hot keys on the main run
                // loop, so this is the main actor and not a hop.
                MainActor.assumeIsolated { service.toggle() }
                return noErr
            },
            1,
            &spec,
            context,
            &handler
        )
        guard installed == noErr else {
            Log.app.error("Palette hot-key handler refused: \(installed)")
            return
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            // Almost always another app already owning ⌃⌥K. The palette
            // simply has no shortcut rather than fighting for it.
            Log.app.error("⌃⌥K is unavailable: \(status)")
            hotKey = nil
        }
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        if let handler {
            RemoveEventHandler(handler)
        }
        handler = nil
    }

    private func toggle() {
        if store.isPaletteOpen {
            store.closePalette()
        } else {
            store.openPalette()
        }
    }

    private func run(_ id: PaletteCommandID) {
        switch id {
        case .playPause: store.nowPlayingCommands?.togglePlayPause()
        case .nextTrack: store.nowPlayingCommands?.next()
        case .previousTrack: store.nowPlayingCommands?.previous()
        case .toggleMute: store.volumeCommands?.toggleMute()
        case .openSettings: showSettings()
        case .replayWelcome: store.onboardingCommands?.replay()
        case .quit: NSApplication.shared.terminate(nil)
        case .keepAwake: system.toggleKeepAwake()
        case .lockScreen: system.lockScreen()
        case .sleepDisplay: system.sleepDisplay()
        case .toggleDarkMode: system.toggleDarkMode()
        case .toggleMicrophone: system.toggleMicrophoneMute()
        case .takeScreenshot: system.openScreenshotTool()
        case .openDownloads: system.openDownloads()
        case .copyTrack: copyCurrentTrack()
        case .searchTrack: searchCurrentTrack()
        case .timerFive: store.timerCommands?.start(5 * 60)
        case .timerTwentyFive: store.timerCommands?.start(25 * 60)
        }
    }

    /// "Artist — Title", or just the title when the source app reports no
    /// artist. One string for both commands, so what is copied is exactly
    /// what is searched for.
    private func trackDescription() -> String? {
        guard let info = store.nowPlaying else { return nil }
        guard let artist = info.artist, !artist.isEmpty else { return info.title }
        return "\(artist) — \(info.title)"
    }

    private func copyCurrentTrack() {
        guard let description = trackDescription() else { return }
        system.copyToPasteboard(description)
    }

    private func searchCurrentTrack() {
        guard let description = trackDescription() else { return }
        system.searchTheWeb(for: description)
    }
}
