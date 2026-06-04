import SwiftUI

@main
struct FaderApp: App {
    @State private var engine: MixerEngine

    init() {
        let engine = MixerEngine()
        _engine = State(initialValue: engine)
        // Start from a queued main-actor task, not init: saved volumes still
        // apply right after launch, but the menu bar icon appears even if the
        // first HAL call blocks on an unresponsive coreaudiod.
        Task { @MainActor in
            engine.start()
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
