import AppKit

// Mirrors of two private CoreGraphics/SkyLight declarations:
//   bool CGSIsScreenWatcherPresent(void);
//   bool CGSRegisterNotifyProc(void (*)(int, int, int, void *), int, void *);
// Same private-API risk class the island's `SkyLightPin` already accepts. If
// either symbol goes away in a future macOS the app fails to launch rather
// than degrading, which is why they are resolved with `dlsym` below rather
// than `@_silgen_name` — the reference used the latter and would crash.
private typealias CGSIsScreenWatcherPresent = @convention(c) () -> Bool
private typealias CGSRegisterNotifyProc = @convention(c) (
    (@convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
    Int32,
    UnsafeMutableRawPointer?
) -> Bool

/// Shows an indicator while the screen is being recorded or shared.
///
/// Event-driven: `CGSRegisterNotifyProc` hands the window server a callback
/// for the two screen-watcher events, and nothing runs until one fires. The
/// elapsed time is not ticked — `store.screenRecording` holds the start date
/// and `TimelineView` draws the clock, the same anchor pattern `IslandTimer`
/// uses.
@MainActor
final class ScreenRecordingService: NotchService {
    private let store: NotchStore
    private var isRegistered = false
    private var isRecording = false

    /// Window-server event numbers for a screen watcher connecting and
    /// disconnecting. Undocumented, like the levels in `SkyLightPin`.
    private static let watcherConnected: Int32 = 1502
    private static let watcherDisconnected: Int32 = 1503

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard !isRegistered else { return }
        guard let register = Self.registerProc else {
            Log.screenRecording.notice("CGSRegisterNotifyProc unavailable; recording indicator disabled")
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: @convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void = { _, _, _, context in
            guard let context else { return }
            let service = Unmanaged<ScreenRecordingService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.refresh() }
        }
        let connected = register(callback, Self.watcherConnected, context)
        let disconnected = register(callback, Self.watcherDisconnected, context)
        isRegistered = connected || disconnected
        guard isRegistered else {
            Log.screenRecording.notice("Screen-watcher notifications refused; recording indicator disabled")
            return
        }
        refresh()
    }

    /// There is no unregister counterpart in the private API. The callback
    /// checks `isRegistered` before doing anything, so after `stop()` it is
    /// inert — the process owns it either way and it dies with us.
    func stop() {
        isRegistered = false
        isRecording = false
        store.screenRecording = nil
        store.deactivate(.screenRecording)
    }

    private func refresh() {
        guard isRegistered, let isPresent = Self.isWatcherPresent else { return }
        let recording = isPresent()
        guard recording != isRecording else { return }
        isRecording = recording
        if recording {
            store.screenRecording = ScreenRecording(startedAt: .now)
            store.activate(.screenRecording)
        } else {
            store.screenRecording = nil
            store.deactivate(.screenRecording)
        }
    }

    private static let handle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics",
        RTLD_NOW
    )

    private static let isWatcherPresent: CGSIsScreenWatcherPresent? = {
        guard let handle, let symbol = dlsym(handle, "CGSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(symbol, to: CGSIsScreenWatcherPresent.self)
    }()

    private static let registerProc: CGSRegisterNotifyProc? = {
        guard let handle, let symbol = dlsym(handle, "CGSRegisterNotifyProc") else { return nil }
        return unsafeBitCast(symbol, to: CGSRegisterNotifyProc.self)
    }()
}
