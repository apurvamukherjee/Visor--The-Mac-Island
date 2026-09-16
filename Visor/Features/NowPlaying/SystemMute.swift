import CoreAudio
import os

/// System output mute. The media adapter has no mute command — MediaRemote
/// only speaks transport — so this goes at the device instead, which is also
/// what the user means by "mute" when the island is showing a track.
enum SystemMute {
    private static var defaultOutputDevice: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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

    /// Rebuilt per call rather than stored: CoreAudio takes the address
    /// `inout`, and a mutable static is global shared state under Swift 6.
    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// nil when the current output device has no mute property of its own —
    /// common on aggregate and some USB devices, where the UI hides the button
    /// rather than showing one that does nothing.
    static var isMuted: Bool? {
        var address = muteAddress()
        guard let device = defaultOutputDevice,
              AudioObjectHasProperty(device, &address) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        guard status == noErr else { return nil }
        return muted != 0
    }

    static func toggle() {
        guard let device = defaultOutputDevice, let muted = isMuted else { return }
        var address = muteAddress()
        var value = UInt32(muted ? 0 : 1)
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
        if status != noErr {
            Log.nowPlaying.error("Mute failed: \(status)")
        }
    }
}
