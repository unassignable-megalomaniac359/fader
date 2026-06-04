import CoreAudio
import SwiftUI

@main
struct FaderApp: App {
    @State private var engine: MixerEngine

    init() {
        let engine = MixerEngine()
        _engine = State(initialValue: engine)
        // The detached probe gates engine.start(): the first HAL contact
        // happens off the main thread, so a wedged coreaudiod hangs the probe
        // while the menu bar icon renders and shows a waiting state. start()
        // only runs once the HAL has proven responsive.
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
