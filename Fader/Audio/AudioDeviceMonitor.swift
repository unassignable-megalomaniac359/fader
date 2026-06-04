import CoreAudio
import Observation
import os

/// An output-capable audio device.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// CoreAudio UIDs for Bluetooth devices start with the MAC address,
    /// e.g. "50-C0-F0-00-1C-78:output" — IOBluetooth uses the same dashed form.
    func matches(bluetoothID: String) -> Bool {
        uid.lowercased().hasPrefix(bluetoothID.lowercased())
    }

    /// SF Symbol matching the device's transport type.
    var symbolName: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            "airpods.gen3"
        case kAudioDeviceTransportTypeBuiltIn:
            "laptopcomputer"
        case kAudioDeviceTransportTypeUSB:
            "cable.connector"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            "display"
        case kAudioDeviceTransportTypeAirPlay:
            "airplay.audio"
        default:
            "hifispeaker"
        }
    }
}

/// Watches output devices and the system default, and switches the default.
@MainActor
@Observable
final class AudioDeviceMonitor {
    private static let logger = Logger(subsystem: "dev.pantafive.fader", category: "AudioDeviceMonitor")

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultDeviceID = AudioDeviceID.unknown

    @ObservationIgnored private var listeners: [HALListener] = []
    // Not observed: stamps change on every refresh, but the view only needs
    // them re-read when defaultDeviceID (observed) moves a device between
    // the main list and the rarely-used group.
    @ObservationIgnored private var lastUsed: [String: Date] = [:]
    @ObservationIgnored private let usageStore = DeviceUsageStore()

    func start() {
        lastUsed = usageStore.load()
        listeners = [
            AudioObjectID.system.listen(kAudioHardwarePropertyDevices) {
                Task { @MainActor [weak self] in self?.refresh() }
            },
            AudioObjectID.system.listen(kAudioHardwarePropertyDefaultOutputDevice) {
                Task { @MainActor [weak self] in self?.refresh() }
            },
        ]
        refresh()
    }

    func setDefault(_ device: AudioDevice) {
        do {
            try AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, value: device.id)
            defaultDeviceID = device.id
        } catch {
            Self.logger.error("Failed to set default output to \(device.name): \(error.localizedDescription)")
        }
    }

    /// True when the device hasn't been the default output within the
    /// retention window. The current default is always "in use" regardless of
    /// its stamp — a fresh switch stamps asynchronously, on the next refresh.
    func isRarelyUsed(_ device: AudioDevice) -> Bool {
        device.id != defaultDeviceID && !DeviceUsageStore.isRecent(lastUsed[device.uid])
    }

    func refresh() {
        defaultDeviceID = (try? AudioObjectID.readDefaultOutputDevice()) ?? .unknown
        stampDefaultDevice()

        guard let ids = try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, of: AudioDeviceID.self)
        else {
            Self.logger.error("Failed to read device list")
            return
        }

        devices = ids.compactMap { id in
            guard id.outputChannelCount() > 0,
                  let uid = try? id.readDeviceUID(),
                  let name = try? id.readString(kAudioObjectPropertyName)
            else { return nil }
            var transport: UInt32 = 0
            try? id.read(kAudioDevicePropertyTransportType, into: &transport)
            // Private aggregates (including Fader's own tap devices) are plumbing,
            // not user choices.
            guard transport != kAudioDeviceTransportTypeAggregate || !name.hasPrefix("Fader") else { return nil }
            return AudioDevice(id: id, uid: uid, name: name, transport: transport)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Records that the current default output is in use. Writes are throttled
    /// to one per hour per device — ample granularity for a 30-day window.
    private func stampDefaultDevice(now: Date = Date()) {
        guard defaultDeviceID != .unknown, let uid = try? defaultDeviceID.readDeviceUID() else { return }
        if let stamp = lastUsed[uid], now.timeIntervalSince(stamp) < 3600 { return }
        lastUsed[uid] = now
        usageStore.save(lastUsed, now: now)
    }
}

extension AudioObjectID {
    /// Total output channels across all output streams.
    func outputChannelCount() -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let listPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { listPtr.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, listPtr) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
