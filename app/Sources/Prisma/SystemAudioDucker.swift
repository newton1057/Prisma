import Foundation
import CoreAudio

/// macOS does not expose a public per-app ducking API. To keep music, videos or
/// calls in the background while Prisma speaks, we ramp the default output
/// device volume down and let the speech engine compensate its own level with a
/// limiter. When speech ends the previous volume is restored with a short ramp.
///
/// All methods are expected to be called from the main thread.
final class SystemAudioDucker {
    private var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var baseVolume: Float = 0
    private var duckedVolume: Float = 0
    private var compensationDB: Double = 0
    private var isDucked = false
    private var pendingRestoreTarget: Float?
    private var rampTimer: Timer?
    private var safetyTimer: Timer?

    var ducking: Bool { isDucked }

    /// Lowers the output volume to `factor` of its current value and returns the
    /// gain (in dB) that the speech player must apply to stay at its original
    /// perceived level. Returns 0 when ducking is not possible.
    @discardableResult
    func duck(to factor: Double) -> Double {
        guard let device = Self.defaultOutputDevice(),
              let current = Self.volume(for: device),
              current > 0.02 else {
            return 0
        }

        let wasDucked = isDucked && device == deviceID
        let baseline: Float
        if wasDucked {
            baseline = baseVolume
        } else if let pending = pendingRestoreTarget {
            rampTimer?.invalidate()
            rampTimer = nil
            pendingRestoreTarget = nil
            baseline = max(pending, current)
        } else {
            baseline = current
        }

        let clampedFactor = min(0.85, max(0.10, factor))
        let target = max(0.015, baseline * Float(clampedFactor))
        guard target < baseline - 0.005 else {
            return wasDucked ? compensationDB : 0
        }

        deviceID = device
        baseVolume = baseline
        duckedVolume = target
        compensationDB = min(12.0, max(0.0, 20.0 * log10(Double(baseline / target))))
        isDucked = true

        if abs(target - current) > 0.002 {
            ramp(from: current, to: target, duration: wasDucked ? 0.3 : 0.35)
        }
        scheduleSafetyRestore()
        return compensationDB
    }

    /// Refreshes the safety timeout while speech is still progressing, so a
    /// long message does not trip the watchdog mid-sentence.
    func keepAlive() {
        guard isDucked else { return }
        scheduleSafetyRestore()
    }

    /// Restores the volume with a smooth ramp. Safe to call at any time.
    func restore() {
        let wasRamping = rampTimer != nil
        rampTimer?.invalidate()
        rampTimer = nil
        safetyTimer?.invalidate()
        safetyTimer = nil

        guard isDucked, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            pendingRestoreTarget = nil
            return
        }
        isDucked = false
        compensationDB = 0

        guard let current = Self.volume(for: deviceID) else {
            pendingRestoreTarget = nil
            return
        }

        let target = restoreTarget(current: current, wasRamping: wasRamping)
        pendingRestoreTarget = target
        ramp(from: current, to: target, duration: 0.5) { [weak self] in
            self?.pendingRestoreTarget = nil
        }
    }

    /// Restores the volume immediately (used when the app is terminating).
    func restoreImmediately() {
        let wasRamping = rampTimer != nil
        rampTimer?.invalidate()
        rampTimer = nil
        safetyTimer?.invalidate()
        safetyTimer = nil

        guard isDucked || pendingRestoreTarget != nil else {
            compensationDB = 0
            return
        }

        isDucked = false
        compensationDB = 0

        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            pendingRestoreTarget = nil
            return
        }

        if let pending = pendingRestoreTarget {
            pendingRestoreTarget = nil
            Self.setVolume(pending, for: deviceID)
            return
        }

        guard let current = Self.volume(for: deviceID) else { return }
        Self.setVolume(restoreTarget(current: current, wasRamping: wasRamping), for: deviceID)
    }

    private func restoreTarget(current: Float, wasRamping: Bool) -> Float {
        // If the ramp had not finished yet, the volume is simply in transit.
        // If the user moved the volume while Prisma was speaking, respect their
        // setting instead of overriding it. Otherwise restore the level we took.
        if wasRamping || abs(current - duckedVolume) < 0.02 {
            return baseVolume
        }
        return current
    }

    private func scheduleSafetyRestore() {
        safetyTimer?.invalidate()
        let timer = Timer(timeInterval: 600, repeats: false) { [weak self] _ in
            self?.restore()
        }
        safetyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func ramp(
        from start: Float,
        to target: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        rampTimer?.invalidate()

        let steps = max(2, Int(duration * 60))
        let interval = duration / Double(steps)
        var step = 0

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            step += 1
            let progress = min(1.0, Float(step) / Float(steps))
            let eased = 1 - pow(1 - progress, 2)
            Self.setVolume(start + (target - start) * eased, for: self.deviceID)

            if step >= steps {
                timer.invalidate()
                if self.rampTimer === timer {
                    self.rampTimer = nil
                }
                completion?()
            }
        }

        rampTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func volume(for device: AudioDeviceID) -> Float? {
        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return nil }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return volume
    }

    private static func setVolume(_ volume: Float, for device: AudioDeviceID) {
        var address = volumeAddress
        var value = max(0, min(1, volume))
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
