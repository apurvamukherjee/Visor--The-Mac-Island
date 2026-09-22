import AppKit
import CoreAudio
import ImageIO
import IOKit.pwr_mgt
import UniformTypeIdentifiers

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

    func openDownloads() {
        guard let url = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        NSWorkspace.shared.open(url)
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

    private func run(_ path: String, _ arguments: [String]) {
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

/// The file commands. Split from the class for length: these all act on
/// one URL from the shelf and share nothing with the power and audio ones
/// above.
@MainActor
extension SystemCommands {
    // MARK: - Files

    static func isArchive(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .archive) ?? false
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// A plain Markdown file in Application Support, opened in whatever the
    /// user reads Markdown with. Deliberately **not** `~/Documents`: that
    /// directory is TCC-gated on a modern macOS, and a note-taking command
    /// that raises a permission dialog is not a quick note.
    func makeQuickNote() {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Visor", isDirectory: true) else { return }
        let url = directory.appendingPathComponent("Notes.md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)
            let entry = "\n## \(stamp)\n\n"
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            } else {
                try Data("# Visor Notes\n\(entry)".utf8).write(to: url)
            }
        } catch {
            Log.app.error("Quick note failed: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// `NSFileCoordinator`'s `.forUploading` — the documented way to get a
    /// zip of any file *or* folder without a third-party archiver. It hands
    /// back a temporary copy, which is why this moves the result rather than
    /// writing in place.
    func compress(_ url: URL) {
        var error: NSError?
        var moved = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.forUploading], error: &error) { zipped in
            let destination = Self.available(url.deletingPathExtension().appendingPathExtension("zip"))
            do {
                try FileManager.default.copyItem(at: zipped, to: destination)
                moved = true
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                Log.app.error("Compress failed: \(error.localizedDescription)")
            }
        }
        if let error, !moved {
            Log.app.error("Compress failed: \(error.localizedDescription)")
        }
    }

    /// `ditto -x -k`, because Foundation has no unarchiver at all — only the
    /// `.forUploading` trick in the other direction.
    func expand(_ url: URL) {
        let destination = Self.available(
            url.deletingPathExtension(),
            isDirectory: true
        )
        run("/usr/bin/ditto", ["-x", "-k", url.path, destination.path])
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// ImageIO, already linked for artwork decoding. 0.9 rather than 1.0:
    /// the point of converting a screenshot to JPEG is that it gets smaller.
    func convertToJPEG(_ url: URL) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Log.app.error("Could not read \(url.lastPathComponent) as an image.")
            return
        }
        let destination = Self.available(url.deletingPathExtension().appendingPathExtension("jpg"))
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            Log.app.error("Could not write \(destination.lastPathComponent).")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Never overwrite what is already there. A command run twice should
    /// produce a second file, not destroy the first one's result.
    private static func available(_ url: URL, isDirectory: Bool = false) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        for suffix in 2 ... 99 {
            var candidate = base.appendingPathExtension("")
            candidate = URL(fileURLWithPath: "\(base.path) \(suffix)", isDirectory: isDirectory)
            if !ext.isEmpty {
                candidate = candidate.appendingPathExtension(ext)
            }
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return url
    }
}

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
