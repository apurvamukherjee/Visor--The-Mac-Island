import AppKit
import CoreAudio
import IOKit.pwr_mgt

/// The side effects the palette runs. Kept apart from `PaletteService`, which
/// is about one hot key and nothing else.
///
/// Every mechanism here was measured on a throwaway probe first, from an
/// ad-hoc-signed bundle launched through LaunchServices so it carried its own
/// TCC identity (`AXIsProcessTrusted() == false`). **Nothing below needs a
/// permission.** What the probe ruled *out* is recorded at the bottom.
@MainActor
final class SystemCommands {
    /// Held for as long as the island is keeping the Mac awake. Its presence
    /// *is* the state — there is nothing else to store.
    private var sleepAssertion: IOPMAssertionID?

    var isKeepingAwake: Bool {
        sleepAssertion != nil
    }

    func stop() {
        releaseSleepAssertion()
    }

    // MARK: - Power

    func toggleKeepAwake() {
        if sleepAssertion != nil {
            releaseSleepAssertion()
            return
        }
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            // Display sleep, not idle sleep: "keep awake" means the screen
            // stays on for a download or a long read, and preventing idle
            // sleep alone would still let the display go dark.
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Visor — Keep Awake" as CFString,
            &id
        )
        guard status == kIOReturnSuccess else {
            Log.app.error("Could not hold a sleep assertion: \(status)")
            return
        }
        sleepAssertion = id
    }

    private func releaseSleepAssertion() {
        guard let sleepAssertion else { return }
        IOPMAssertionRelease(sleepAssertion)
        self.sleepAssertion = nil
    }

    /// `SACLockScreenImmediate` from the private login framework — the same
    /// call the menu bar's own "Lock Screen" makes. Resolved with `dlsym` so
    /// a missing symbol on some future macOS degrades to doing nothing,
    /// rather than failing to launch the way a `@_silgen_name` binding would.
    func lockScreen() {
        typealias LockFn = @convention(c) () -> Int32
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login", RTLD_NOW),
            let symbol = dlsym(handle, "SACLockScreenImmediate")
        else {
            Log.app.error("Lock screen is unavailable on this system.")
            return
        }
        _ = unsafeBitCast(symbol, to: LockFn.self)()
    }

    /// `pmset displaysleepnow` — a user-level tool, no root and no prompt.
    /// There is no public API for "sleep the display now"; every IOKit route
    /// to it needs privileges this app does not have and should not ask for.
    func sleepDisplay() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    // MARK: - Appearance

    /// Verified by probe on 2026-09-23: read the current theme, write the
    /// opposite, read it back, restore. The write took and the restore took.
    func toggleDarkMode() {
        typealias GetFn = @convention(c) () -> Bool
        typealias SetFn = @convention(c) (Bool) -> Void
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
            let get = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
            let set = dlsym(handle, "SLSSetAppearanceThemeLegacy")
        else {
            Log.app.error("Appearance switching is unavailable on this system.")
            return
        }
        let isDark = unsafeBitCast(get, to: GetFn.self)()
        unsafeBitCast(set, to: SetFn.self)(!isDark)
    }

    // MARK: - Microphone

    /// The default *input* device's mute. Not every input has one — the
    /// probe found a Continuity iPhone microphone with no mute property at
    /// all — so the command is only offered when the current input can
    /// actually be muted.
    static var hasMutableMicrophone: Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    func toggleMicrophoneMute() {
        guard let device = Self.defaultInputDevice() else { return }
        var address = Self.muteAddress()
        var current = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr else {
            Log.app.error("Could not read the microphone's mute state.")
            return
        }
        var flipped = current == 0 ? UInt32(1) : UInt32(0)
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &flipped
        )
        if status != noErr {
            Log.app.error("Could not set the microphone's mute state: \(status)")
        }
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    // MARK: - Opening things

    /// Apple's own Screenshot app rather than spawning `screencapture -i`.
    /// The binary would be slicker, but a capture spawned by Visor could put
    /// the Screen Recording prompt on *Visor's* name, and that is a
    /// permission this app has never asked for. Screenshot.app owns its own.
    /// Whatever it writes, `ScreenshotService` catches on the shelf anyway.
    func openScreenshotTool() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The app a force quit would actually end, or nil when there is nothing
    /// sensible to end.
    ///
    /// **Visor is excluded** for the obvious reason, and it is not a
    /// hypothetical: the palette's panel is `.nonactivatingPanel`, so Visor is
    /// never frontmost while the palette is open — which is exactly why this
    /// reads the right app, and exactly why the guard has to be explicit
    /// rather than relying on that.
    ///
    /// **The Finder is excluded** because force-quitting it is what Apple's
    /// own window renames to "Relaunch": it comes straight back, so a row
    /// saying "Force Quit Finder" would be describing something that does not
    /// happen.
    static var forceQuitTarget: NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.finder"
        else {
            return nil
        }
        return app
    }

    /// `forceTerminate()` is public API and costs no permission at all.
    ///
    /// Worth stating plainly, because the obvious route does: the
    /// Accessibility prompt ⌘⌥Esc would have needed is the price of
    /// *synthesising a keystroke*, not of ending a process. macOS has always
    /// let an app SIGKILL another app the same user is running.
    func forceQuitFrontmostApp() {
        guard let app = Self.forceQuitTarget else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "an application"
        guard app.forceTerminate() else {
            Log.app.error("Could not force quit \(name, privacy: .public)")
            return
        }
    }

    func openDownloads() {
        guard let url = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// A bundle identifier resolves through `NSWorkspace`, not a stored path —
    /// an app that moved inside `/Applications` still launches; only one
    /// actually removed does not. Already running is not an error:
    /// `openApplication` activates it instead of relaunching, so firing the
    /// same group twice is harmless. `resolve` is injectable so a missing app
    /// can be exercised in a test without installing or removing anything.
    func launch(_ group: LaunchGroup, resolve: (String) -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }) {
        for app in group.apps {
            guard let url = resolve(app.bundleIdentifier) else {
                Log.app.error("Launch group app not found: \(app.bundleIdentifier)")
                continue
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func searchTheWeb(for query: String) {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Audio output

    /// Cycles to the next output device. A palette row per device would be
    /// better, but the command list is a static value — dynamic rows mean a
    /// string identifier and the end of the exhaustive switch that makes
    /// adding a command safe. Cycling covers the case that actually happens:
    /// built-in speakers to headphones and back.
    static var hasMultipleOutputs: Bool {
        outputDevices().count > 1
    }

    func cycleAudioOutput() {
        let devices = Self.outputDevices()
        guard devices.count > 1 else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &current
        ) == noErr else { return }

        let index = devices.firstIndex(of: current) ?? -1
        var next = devices[(index + 1) % devices.count]
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &next
        )
        if status != noErr {
            Log.app.error("Could not switch the output device: \(status)")
        }
    }

    /// Every device with at least one output stream. A device with none is
    /// an input, and offering it as an output silently does nothing.
    private static func outputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids.filter { hasOutputStreams($0) }
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    /// Not `private`: `SystemCommands+Files.swift`'s `expand` shells out to
    /// `ditto` through this same helper.
    func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            Log.app.error("\(path) failed: \(error.localizedDescription)")
        }
    }
}

// File commands (compress/expand/convert/quick note) live in
// SystemCommands+Files.swift — split out for length, and because they share
// nothing with the power, appearance, and audio commands above.
//
// Ruled out by the same probe, each for a measured reason:
//
// - **Empty Trash.** `~/.Trash` is not even listable without Full Disk
//   Access — the probe got nil back for its contents. Same wall as the
//   notification mirroring that was cut in 2026-09-16.
// - **Night Shift.** `CBBlueLightClient` exists and loads, but driving it
//   from Swift means hand-declaring an ObjC interface for a class with no
//   header, to pass a primitive `BOOL`. That is the `@_silgen_name` class of
//   binding this codebase already replaced once for being brittle.
// - **`screencapture -i`.** Works, but see `openScreenshotTool` — the TCC
//   attribution is the risk, not the call.
