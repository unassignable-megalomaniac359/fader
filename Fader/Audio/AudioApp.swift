import AppKit
import CoreAudio

/// A running application that the HAL knows as an audio process.
struct AudioApp: Identifiable, Hashable {
    let id: pid_t
    let bundleID: String
    let name: String
    let objectID: AudioObjectID
    let isPlaying: Bool

    /// App icon resolved through NSRunningApplication; cheap, AppKit caches it.
    @MainActor
    var icon: NSImage {
        NSRunningApplication(processIdentifier: id)?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
