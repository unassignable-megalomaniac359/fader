import AudioToolbox
import CoreAudio
import Observation

/// What a volume slider binds to: the system default's volume
/// (SystemVolumeController) or one concrete device's (DeviceVolumeController).
@MainActor
protocol VolumeControlling: AnyObject, Observable {
    var volume: Float { get }
    var isMuted: Bool { get }
    var canSetVolume: Bool { get }
    var canMute: Bool { get }
    func setVolume(_ value: Float)
    func toggleMute()
}

extension SystemVolumeController: VolumeControlling {}

/// Volume and mute of one pinned output device. Multi-output members keep
/// their own HAL volume — the stacked aggregate exposes no master control,
/// so these per-device controllers are the only volume there is.
@MainActor
@Observable
final class DeviceVolumeController: VolumeControlling {
    let deviceID: AudioObjectID

    private(set) var volume: Float = 1.0
    private(set) var isMuted = false
    private(set) var canSetVolume = true
    private(set) var canMute = true

    @ObservationIgnored private var listeners: [HALListener] = []

    init(deviceID: AudioObjectID) {
        self.deviceID = deviceID
        canSetVolume = deviceID.isSettable(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                           scope: kAudioDevicePropertyScopeOutput)
        canMute = deviceID.isSettable(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        listeners = [
            deviceID.listen(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                            scope: kAudioDevicePropertyScopeOutput) {
                Task { @MainActor [weak self] in self?.readBack() }
            },
            deviceID.listen(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) {
                Task { @MainActor [weak self] in self?.readBack() }
            },
        ]
        readBack()
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        do {
            try deviceID.write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                               scope: kAudioDevicePropertyScopeOutput,
                               value: clamped)
            volume = clamped
        } catch {
            readBack() // keep published state honest when the HAL write fails
        }
    }

    func toggleMute() {
        let next: UInt32 = isMuted ? 0 : 1
        do {
            try deviceID.write(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, value: next)
            isMuted = next != 0
        } catch {
            readBack()
        }
    }

    private func readBack() {
        var value: Float32 = 1.0
        if (try? deviceID.read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                               scope: kAudioDevicePropertyScopeOutput,
                               into: &value)) != nil {
            volume = value
        }
        var muted: UInt32 = 0
        if (try? deviceID.read(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput,
                               into: &muted)) != nil {
            isMuted = muted != 0
        }
    }
}
