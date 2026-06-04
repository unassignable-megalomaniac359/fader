import AudioToolbox
import CoreAudio
import Observation
import os

/// Reads and writes the default output device's main volume and mute,
/// staying in sync with changes made elsewhere (volume keys, Control Center).
@MainActor
@Observable
final class SystemVolumeController {
    private static let logger = Logger(subsystem: "dev.pantafive.fader", category: "SystemVolume")

    private(set) var volume: Float = 1.0
    private(set) var isMuted = false
    private(set) var deviceName = ""

    @ObservationIgnored private var device = AudioObjectID.unknown
    @ObservationIgnored private var listeners: [HALListener] = []

    func start() {
        listeners.append(AudioObjectID.system.listen(kAudioHardwarePropertyDefaultOutputDevice) {
            Task { @MainActor [weak self] in self?.attachToDefaultDevice() }
        })
        attachToDefaultDevice()
    }

    func setVolume(_ value: Float) {
        volume = max(0, min(1, value))
        try? device.write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                          scope: kAudioDevicePropertyScopeOutput,
                          value: volume)
    }

    func toggleMute() {
        let next: UInt32 = isMuted ? 0 : 1
        try? device.write(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, value: next)
        isMuted.toggle()
    }

    // MARK: - Private

    private func attachToDefaultDevice() {
        guard let next = try? AudioObjectID.readDefaultOutputDevice(), next.isValid else { return }
        device = next
        deviceName = (try? device.readString(kAudioObjectPropertyName)) ?? ""

        listeners = [listeners[0]]
        listeners.append(device.listen(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                       scope: kAudioDevicePropertyScopeOutput) {
                Task { @MainActor [weak self] in self?.readBack() }
            })
        listeners.append(device.listen(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) {
            Task { @MainActor [weak self] in self?.readBack() }
        })
        readBack()
    }

    private func readBack() {
        var value: Float32 = 1.0
        if (try? device.read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                             scope: kAudioDevicePropertyScopeOutput,
                             into: &value)) != nil {
            volume = value
        }
        var muted: UInt32 = 0
        if (try? device.read(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, into: &muted)) != nil {
            isMuted = muted != 0
        }
    }
}
