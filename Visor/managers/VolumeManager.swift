//
//  VolumeManager.swift
//  
//
//  Created by Apurva on 22/08/2025.
//

import AppKit
import Combine
import CoreAudio
import Foundation

final class VolumeManager: NSObject, ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var rawVolume: Float = 0

    private let step: Float32 = 1.0 / 16.0
    // Fallback software if hardware mute is not supported
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted: Bool = false

    private override init() {
        super.init()
        setupAudioListener()
        fetchCurrentVolume()
    }

    // MARK: - Public Control API
    // Visor: increase and decrease were copies that differed in the sign.
    @MainActor func stepVolume(up: Bool, stepDivisor: Float = 1.0) {
        let delta = step / Float32(max(stepDivisor, 0.25))
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current + (up ? delta : -delta)))
        setAbsolute(target)
        VisorViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func toggleMuteAction() {
        // Determine expected resulting state immediately and show HUD with that value.
        // Visor: isMutedInternal already falls back to softwareMuted for an unknown device.
        let willBeMuted = !isMutedInternal()
        let unmutedVolume = systemOutputDeviceID() == kAudioObjectUnknown
            ? previousVolumeBeforeMute
            : (readVolumeInternal() ?? rawVolume)

        toggleMuteInternal()
        VisorViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(willBeMuted ? 0 : unmutedVolume))
    }

    @MainActor func setAbsolute(_ value: Float32) {
        let clamped = max(0, min(1, value))
        let currentlyMuted = isMutedInternal()
        if currentlyMuted && clamped > 0 {
            toggleMuteInternal()
        }

        writeVolumeInternal(clamped)

        if clamped == 0 && !currentlyMuted {
            toggleMuteInternal()
        }

        publish(volume: clamped)
    }

    // MARK: - CoreAudio Helpers
    private func systemOutputDeviceID() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        if status != noErr { return kAudioObjectUnknown }
        return defaultDeviceID
    }

    private func fetchCurrentVolume() {
        guard let volume = readVolumeInternal() else { return }
        publish(volume: max(0, min(1, volume)))
    }

    private func setupAudioListener() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }

        func listen(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: UInt32) -> Bool {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
            guard AudioObjectHasProperty(objectID, &address) else { return false }
            AudioObjectAddPropertyListenerBlock(objectID, &address, nil) { _, _ in
                self.fetchCurrentVolume()
            }
            return true
        }

        _ = listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                   scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
        if !listen(deviceID, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: kAudioObjectPropertyElementMain) {
            for channel in [UInt32(1), UInt32(2)] {
                _ = listen(deviceID, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: channel)
            }
        }
        _ = listen(deviceID, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: kAudioObjectPropertyElementMain)
    }

    private func readVolumeInternal() -> Float32? {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return nil }
        var collected: [Float32] = []
        for el in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            if let v = readValidatedScalar(deviceID: deviceID, element: el) { collected.append(v) }
        }
        guard !collected.isEmpty else { return nil }
        return collected.reduce(0, +) / Float32(collected.count)
    }

    private func writeVolumeInternal(_ value: Float32) {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return }
        let newVal = max(0, min(1, value))

        // Devices without a main volume take it per channel
        if !writeValidatedScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: newVal) {
            for el in [UInt32](1...4) {
                _ = writeValidatedScalar(deviceID: deviceID, element: el, value: newVal)
            }
        }
    }

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    // Visor: nil when the device has no readable hardware mute; isMutedInternal
    // and toggleMuteInternal both fell back to the software mute then.
    private func readHardwareMute(_ deviceID: AudioObjectID) -> Bool? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var muteAddr = Self.muteAddress
        guard AudioObjectHasProperty(deviceID, &muteAddr) else { return nil }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else { return nil }
        var muted: UInt32 = 0
        var size = sizeNeeded
        guard AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    private func isMutedInternal() -> Bool {
        readHardwareMute(systemOutputDeviceID()) ?? softwareMuted
    }

    private func toggleMuteInternal() {
        let deviceID = systemOutputDeviceID()
        // readVolumeInternal is nil for an unknown device, so that case still uses rawVolume
        guard let muted = readHardwareMute(deviceID) else {
            performSoftwareMuteToggle(currentVolume: readVolumeInternal() ?? rawVolume)
            return
        }
        var muteAddr = Self.muteAddress
        var newVal: UInt32 = muted ? 0 : 1
        AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &newVal)
        publish(volume: readVolumeInternal() ?? rawVolume)
    }

    private func performSoftwareMuteToggle(currentVolume: Float32) {
        if softwareMuted {
            let restore = max(0, min(1, previousVolumeBeforeMute))
            writeVolumeInternal(restore)
            softwareMuted = false
            publish(volume: restore)
        } else {
            if currentVolume > 0.001 { previousVolumeBeforeMute = currentVolume }
            writeVolumeInternal(0)
            softwareMuted = true
            publish(volume: 0)
        }
    }

    private func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return nil }
        var vol = Float32(0)
        var size = sizeNeeded
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        return status == noErr ? vol : nil
    }

    private func writeValidatedScalar(deviceID: AudioObjectID, element: UInt32, value: Float32)
        -> Bool
    {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return false }
        var val = value
        return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, sizeNeeded, &val) == noErr
    }

    private func publish(volume: Float32) {
        DispatchQueue.main.async {
            self.rawVolume = volume
        }
    }
}
