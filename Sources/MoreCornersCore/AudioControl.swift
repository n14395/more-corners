// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import CoreAudio
import Foundation

/// Mutes/unmutes the default audio input device — the "am I muted?" panic
/// button for calls. Prefers the device's own mute control; devices without
/// one fall back to zeroing the input volume and restoring it on unmute.
/// CoreAudio only — needs no permissions.
enum AudioInput {

    private static let savedVolumeKey = "micMute.savedInputVolume"
    /// Elements to probe: the main (whole-device) control, then channels 1/2 —
    /// many devices only expose per-channel controls.
    private static let elements: [AudioObjectPropertyElement] =
        [kAudioObjectPropertyElementMain, 1, 2]

    /// Toggle mute on the default input device. Returns the new muted state,
    /// or nil when there is no input device or no controllable property.
    @discardableResult
    static func toggleMute() -> Bool? {
        guard let device = defaultInputDevice() else { return nil }

        // Preferred: the device's own mute control.
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyMute, element: element)
            guard AudioObjectHasProperty(device, &address), isSettable(device, &address),
                  let muted = read(device, &address, UInt32(0)) else { continue }
            let newValue: UInt32 = muted == 0 ? 1 : 0
            // Set every element that exists so multi-channel devices stay in sync.
            for target in elements {
                var a = inputAddress(kAudioDevicePropertyMute, element: target)
                if AudioObjectHasProperty(device, &a), isSettable(device, &a) {
                    write(device, &a, newValue)
                }
            }
            return newValue == 1
        }

        // Fallback: no mute control — zero the input volume, restore on unmute.
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            guard AudioObjectHasProperty(device, &address), isSettable(device, &address),
                  let volume = read(device, &address, Float32(0)) else { continue }
            let defaults = UserDefaults.standard
            if volume > 0.001 {
                defaults.set(Double(volume), forKey: savedVolumeKey)
                setInputVolume(device, 0)
                return true
            } else {
                let saved = defaults.object(forKey: savedVolumeKey) as? Double ?? 0.75
                setInputVolume(device, Float32(saved))
                return false
            }
        }
        return nil
    }

    /// The current muted state (mute control if present, else volume ≈ 0), or
    /// nil when it can't be determined. Used by the E2E harness.
    static func isMuted() -> Bool? {
        guard let device = defaultInputDevice() else { return nil }
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyMute, element: element)
            if AudioObjectHasProperty(device, &address),
               let muted = read(device, &address, UInt32(0)) {
                return muted == 1
            }
        }
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            if AudioObjectHasProperty(device, &address),
               let volume = read(device, &address, Float32(0)) {
                return volume <= 0.001
            }
        }
        return nil
    }

    // MARK: - CoreAudio plumbing

    private static func defaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector,
                                     element: AudioObjectPropertyElement)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeInput,
                                   mElement: element)
    }

    private static func setInputVolume(_ device: AudioObjectID, _ value: Float32) {
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            if AudioObjectHasProperty(device, &address), isSettable(device, &address) {
                write(device, &address, value)
            }
        }
    }

    private static func isSettable(_ device: AudioObjectID,
                                   _ address: inout AudioObjectPropertyAddress) -> Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    // T is always a trivial CoreAudio value type (UInt32 / Float32); the
    // explicit pointer scopes tell the compiler the raw-pointer pass is fine.
    private static func read<T>(_ device: AudioObjectID,
                                _ address: inout AudioObjectPropertyAddress,
                                _ initial: T) -> T? {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer))
        }
        return status == noErr ? value : nil
    }

    private static func write<T>(_ device: AudioObjectID,
                                 _ address: inout AudioObjectPropertyAddress, _ value: T) {
        var v = value
        _ = withUnsafeMutablePointer(to: &v) { pointer in
            AudioObjectSetPropertyData(device, &address, 0, nil,
                                       UInt32(MemoryLayout<T>.size),
                                       UnsafeRawPointer(pointer))
        }
    }
}
