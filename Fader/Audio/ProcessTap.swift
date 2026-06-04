import AudioToolbox
import CoreAudio
import Foundation
import os

/// Owns the Core Audio plumbing that gives Fader control over one app's volume:
/// a process tap that mutes the app's native output, an aggregate device wrapping
/// the real output device, and an IO proc that re-renders the tapped audio with gain.
///
/// Threading: setup and teardown run on the main actor; `volume` and `isMuted` are
/// read lock-free by the real-time HAL IO thread. Aligned Float32/Bool loads and
/// stores are atomic on Apple silicon, so no locking is needed for these.
final class ProcessTap: @unchecked Sendable {
    private static let logger = Logger(subsystem: "dev.pantafive.fader", category: "ProcessTap")

    /// Target gain, 0.0...1.0. Read by the RT thread every buffer.
    private nonisolated(unsafe) var _volume: Float
    /// Mute flag. Read by the RT thread every buffer.
    private nonisolated(unsafe) var _isMuted: Bool
    /// Gain ramped towards `_volume` per frame to avoid clicks. RT thread only.
    private nonisolated(unsafe) var _currentGain: Float
    /// Per-frame ramp coefficient for ~30 ms exponential gain smoothing.
    private nonisolated(unsafe) var _rampCoefficient: Float = 0.0007

    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var procID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "dev.pantafive.fader.io", qos: .userInteractive)

    let processObjectID: AudioObjectID

    var volume: Float {
        get { _volume }
        set { _volume = max(0, min(1, newValue)) }
    }

    var isMuted: Bool {
        get { _isMuted }
        set { _isMuted = newValue }
    }

    init(processObjectID: AudioObjectID, volume: Float = 1.0, isMuted: Bool = false) {
        self.processObjectID = processObjectID
        _volume = volume
        _isMuted = isMuted
        _currentGain = volume
    }

    /// Builds the tap → aggregate → IO proc chain on the given output device.
    @MainActor
    func activate(outputDeviceUID: String) throws {
        guard !aggregateID.isValid else { return }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "Fader tap #\(processObjectID)"

        var tap = AudioObjectID.unknown
        try checked(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
        tapID = tap

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fader aggregate #\(processObjectID)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        var aggregate = AudioObjectID.unknown
        try checked(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
                    "create aggregate device")
        aggregateID = aggregate

        var sampleRate: Float64 = 48000
        try? aggregateID.read(kAudioDevicePropertyNominalSampleRate, into: &sampleRate)
        _rampCoefficient = 1 - exp(-1 / (Float(sampleRate) * 0.030))

        var proc: AudioDeviceIOProcID?
        try checked(
            AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, ioQueue) { [weak self] _, input, _, output, _ in
                guard let self else {
                    Self.silence(output)
                    return
                }
                render(input, into: output)
            },
            "create IO proc"
        )
        procID = proc
        try checked(AudioDeviceStart(aggregateID, procID), "start aggregate device")

        let processID = processObjectID
        Self.logger.info("Tap active for process #\(processID): tap \(tap), aggregate \(aggregate)")
    }

    /// Tears down in the HAL-required order: stop → IO proc → aggregate → tap.
    /// Releasing the tap restores the app's native output.
    @MainActor
    func invalidate() {
        if aggregateID.isValid {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = .unknown
        tapID = .unknown
    }

    deinit {
        // Teardown is idempotent and thread-safe here: by the time deinit runs no
        // other reference exists, and the HAL calls block until the IO proc exits.
        if aggregateID.isValid {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    // MARK: - Real-time path. No allocation, locks, ObjC, or logging below.

    private func render(_ input: UnsafePointer<AudioBufferList>, into output: UnsafeMutablePointer<AudioBufferList>) {
        if _isMuted {
            Self.silence(output)
            return
        }

        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let targetGain = _volume
        var gain = _currentGain
        let ramp = _rampCoefficient

        for (index, outBuffer) in outputs.enumerated() {
            guard let outData = outBuffer.mData else { continue }
            let outSamples = outData.assumingMemoryBound(to: Float.self)
            let outCount = Int(outBuffer.mDataByteSize) / MemoryLayout<Float>.size

            guard index < inputs.count, let inData = inputs[index].mData else {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
                continue
            }
            let inSamples = inData.assumingMemoryBound(to: Float.self)
            let count = min(Int(inputs[index].mDataByteSize) / MemoryLayout<Float>.size, outCount)
            let channels = max(1, Int(outBuffer.mNumberChannels))

            gain = _currentGain
            var frameGain = gain
            for frame in stride(from: 0, to: count, by: channels) {
                frameGain += (targetGain - frameGain) * ramp
                for channel in 0 ..< channels where frame + channel < count {
                    outSamples[frame + channel] = inSamples[frame + channel] * frameGain
                }
            }
            gain = frameGain
            if count < outCount {
                memset(outSamples.advanced(by: count), 0, (outCount - count) * MemoryLayout<Float>.size)
            }
        }
        _currentGain = gain
    }

    private static func silence(_ output: UnsafeMutablePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }
}

/// Converts an OSStatus into a thrown error with context.
func checked(_ status: OSStatus, _ what: @autoclosure () -> String) throws {
    guard status == noErr else {
        throw NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Failed to \(what()): OSStatus \(status)"]
        )
    }
}
