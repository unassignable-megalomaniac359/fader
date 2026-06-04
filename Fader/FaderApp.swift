import CoreAudio
import SwiftUI

@main
struct FaderApp: App {
    @State private var engine: MixerEngine

    init() {
        let engine = MixerEngine()
        _engine = State(initialValue: engine)
        // First HAL contact happens off the main thread: if coreaudiod is
        // unresponsive, the detached probe hangs instead of the UI, and the
        // mixer shows a "waiting for the audio system" state.
        Task.detached(priority: .userInitiated) {
            _ = try? AudioObjectID.readDefaultOutputDevice()
            await MainActor.run {
                engine.start()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Fader", systemImage: "slider.horizontal.3") {
            MixerView()
                .environment(engine)
        }
        .menuBarExtraStyle(.window)
    }
}
