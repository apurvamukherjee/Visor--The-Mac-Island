import CoreAudio
import Foundation
import Observation

/// The volume HUD. macOS never shows Visor the keypress — a global key
/// monitor or a CGEventTap would need Accessibility permission nothing else
/// in the app asks for — but CoreAudio publishes the *result*: the default
/// output device notifies on its volume and mute properties, whoever moved
/// them. Measured on hardware before this was written: F10/F11/F12 each fire
/// within the same runloop turn, from an unsigned binary, with no permission
/// prompt and no monitor.
///
/// Known ceiling: at 0 or 100 the keys change nothing, so CoreAudio emits
/// nothing and the island stays shut where Control Center's HUD would still
/// appear. Closing that gap needs the keypress itself, which is the
/// permission this whole approach exists to avoid.
@MainActor
final class VolumeService: NotchService {
    private let store: NotchStore
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var peekTask: Task<Void, Never>?

    /// Shorter than the charging peek: a volume nudge is acknowledged, not
    /// read.
    private static let peekDuration: TimeInterval = 1.6
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` — the volume
    /// macOS itself moves, rather than the one the hardware happens to own.
    ///
    /// The obvious property, `kAudioDevicePropertyVolumeScalar` on the main
    /// element, exists only on devices with a hardware master control. A
    /// Bluetooth soundbar, most USB DACs and HDMI do not have one, so the
    /// read returned nil and the feature switched itself off — the island
    /// simply never appeared on anything but the built-in speakers.
    ///
    /// Measured on a JBL CINEMA SB510 before this was written: main-element
    /// scalar **absent**, per-channel scalar present but unbalanced (0.38 /
    /// 0.37, so averaging them would drift), and this property present,
    /// settable, and notifying on every system volume change including mute.
    /// On the built-in speakers it returns exactly what the master scalar
    /// returns (0.70 both), so this is a replacement, not a fallback.
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        store.volumeCommands = NotchStore.VolumeCommands(
            setLevel: { [weak self] level in self?.setLevel(level) },
            toggleMute: { [weak self] in self?.toggleMute() }
        )
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor [weak self] in self?.attachToDefaultDevice() }
        }
        if AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, block) == noErr {
            defaultDeviceListener = block
        } else {
            Log.volume.error("Could not observe the default output device.")
        }
        attachToDefaultDevice()
    }

    func stop() {
        peekTask?.cancel()
        peekTask = nil
        detachFromDevice()
        if let defaultDeviceListener {
            var address = Self.address(
                kAudioHardwarePropertyDefaultOutputDevice,
                scope: kAudioObjectPropertyScopeGlobal
            )
            AudioObjectRemovePropertyListenerBlock(Self.system, &address, .main, defaultDeviceListener)
        }
        defaultDeviceListener = nil
        store.volumeCommands = nil
        store.volume = nil
        store.deactivate(.volume)
    }

    /// Plugging in headphones swaps the device out from under us, and the
    /// old object stops notifying — so the listeners move with it.
    private func attachToDefaultDevice() {
        detachFromDevice()
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &id) == noErr else {
            Log.volume.error("Could not read the default output device.")
            return
        }
        device = id
        for selector in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
            var deviceAddress = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            guard AudioObjectHasProperty(device, &deviceAddress) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            guard AudioObjectAddPropertyListenerBlock(device, &deviceAddress, .main, block) == noErr else {
                Log.volume.error("Could not observe output volume.")
                continue
            }
            deviceListeners.append((deviceAddress, block))
        }
        // No peek on the first read of a device: switching output is not the
        // user asking to see the volume, and neither is launching the app.
        refresh(peek: false)
    }

    private func detachFromDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        deviceListeners.removeAll()
    }

    private func refresh(peek: Bool = true) {
        guard let info = read() else {
            // An output with no volume of its own at all — rare now that the
            // read goes through the virtual main volume, which macOS provides
            // in software for anything lacking a hardware control. The feature
            // simply isn't there rather than showing a dead bar.
            store.volume = nil
            store.deactivate(.volume)
            return
        }
        // CoreAudio fires repeatedly for every change — measured at twice on
        // the built-in speakers and 8-16 times on a Bluetooth soundbar, which
        // re-notifies per channel — and once more for the write the slider
        // itself just made. Only a real move peeks.
        guard info != store.volume else { return }
        store.volume = info
        if peek {
            schedulePeek()
        }
    }

    private func read() -> VolumeInfo? {
        guard let level = Self.value(Float32.self, device, Self.virtualMainVolume) else { return nil }
        let muted = Self.value(UInt32.self, device, kAudioDevicePropertyMute) == 1
        return VolumeInfo(level: VolumeInfo.clamped(level), isMuted: muted)
    }

    private func setLevel(_ level: Float) {
        var value = VolumeInfo.clamped(level)
        guard write(Self.virtualMainVolume, &value, MemoryLayout<Float32>.size) else { return }
        // Written straight to the store rather than waiting for the
        // notification, so the bar tracks the pointer instead of the
        // round-trip. The listener that follows agrees and dedupes.
        store.volume = VolumeInfo(level: value, isMuted: store.volume?.isMuted ?? false)
        schedulePeek()
    }

    private func toggleMute() {
        guard let current = store.volume else { return }
        var value: UInt32 = current.isMuted ? 0 : 1
        guard write(kAudioDevicePropertyMute, &value, MemoryLayout<UInt32>.size) else { return }
        store.volume = VolumeInfo(level: current.level, isMuted: !current.isMuted)
        schedulePeek()
    }

    private func write(_ selector: AudioObjectPropertySelector, _ value: UnsafeRawPointer, _ size: Int) -> Bool {
        var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(size), value)
        guard status == noErr else {
            Log.volume.error("Could not write output volume property: \(status)")
            return false
        }
        return true
    }

    private func schedulePeek() {
        store.activate(.volume)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.peekDuration), tolerance: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            peekTask = nil
            dismiss()
        }
    }

    /// Dismissing under the pointer would pull the slider out from under a
    /// drag, so an expanded island waits for its own collapse instead — the
    /// same re-arm the screenshot shelf uses.
    private func dismiss() {
        guard store.state == .expanded else {
            store.deactivate(.volume)
            return
        }
        withObservationTracking {
            _ = store.state
        } onChange: { [weak self] in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T: Numeric>(
        _: T.Type,
        _ device: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> T? {
        var address = address(selector, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = T.zero
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
