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
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    func start() {
        listListener = AudioObjectID.system.listen(kAudioHardwarePropertyProcessObjectList) {
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Coalesces listener bursts: HAL fires once per process and once per
    /// output-state flip, often a dozen times within a few milliseconds.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
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
                  let bundleID = running.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier
            else { continue }

            // Regular apps always; agents and helpers only while they actually
            // play — keeps Control Center, Siri, and GPU helpers out of the mixer.
            let isPlaying = objectID.readProcessIsRunningOutput()
            guard running.activationPolicy == .regular || isPlaying else { continue }

            nextApps.append(AudioApp(
                id: pid,
                bundleID: bundleID,
                name: running.localizedName ?? bundleID,
                objectID: objectID,
                isPlaying: isPlaying
            ))

            // Re-rank rows the moment an app starts or stops playing.
            nextOutputListeners[objectID] = outputListeners[objectID]
                ?? objectID.listen(kAudioProcessPropertyIsRunningOutput) {
                    Task { @MainActor [weak self] in self?.scheduleRefresh() }
                }
        }

        // Playing apps first, then alphabetical; stable for equal keys.
        nextApps.sort {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        outputListeners = nextOutputListeners
        let names = nextApps.map(\.name).joined(separator: ", ")
        Self.logger.info("Apps: \(nextApps.count)/\(objectIDs.count) HAL processes — \(names, privacy: .public)")
        if nextApps != apps {
            apps = nextApps
        }
    }
}
