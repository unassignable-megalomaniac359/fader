import AppKit
import CoreAudio
import Observation
import os

/// Watches the HAL's audio process list and publishes the running apps
/// that can play sound, joined with AppKit metadata (name, icon).
@MainActor
@Observable
final class AudioProcessMonitor {
    private static let logger = Logger(subsystem: "dev.pantafive.fader", category: "AudioProcessMonitor")

    private(set) var apps: [AudioApp] = []

    @ObservationIgnored private var listListener: HALListener?
    @ObservationIgnored private var outputListeners: [AudioObjectID: HALListener] = [:]

    func start() {
        listListener = AudioObjectID.system.listen(kAudioHardwarePropertyProcessObjectList) {
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        guard let objectIDs = try? AudioObjectID.readProcessList() else {
            Self.logger.error("Failed to read HAL process list")
            return
        }

        var nextApps: [AudioApp] = []
        var nextOutputListeners: [AudioObjectID: HALListener] = [:]

        for objectID in objectIDs {
            guard let pid = try? objectID.readProcessPID(),
                  let running = NSRunningApplication(processIdentifier: pid),
                  running.activationPolicy != .prohibited || running.bundleIdentifier != nil,
                  let bundleID = running.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier
            else { continue }

            nextApps.append(AudioApp(
                id: pid,
                bundleID: bundleID,
                name: running.localizedName ?? bundleID,
                objectID: objectID,
                isPlaying: objectID.readProcessIsRunningOutput()
            ))

            // Re-rank rows the moment an app starts or stops playing.
            nextOutputListeners[objectID] = outputListeners[objectID]
                ?? objectID.listen(kAudioProcessPropertyIsRunningOutput) {
                    Task { @MainActor [weak self] in self?.refresh() }
                }
        }

        // Playing apps first, then alphabetical; stable for equal keys.
        nextApps.sort {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        outputListeners = nextOutputListeners
        if nextApps != apps {
            apps = nextApps
        }
    }
}
