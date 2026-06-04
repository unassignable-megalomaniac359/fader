import CoreAudio
import SwiftUI

@main
struct FaderApp: App {
    @State private var engine: MixerEngine
    @State private var statusMenu = StatusItemMenuController()

    init() {
        let engine = MixerEngine()
        _engine = State(initialValue: engine)
        statusMenu.install()
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

    /// SwiftUI's name-based Image fails to resolve loose bundle resources in
    /// a MenuBarExtra label; load via AppKit. isTemplate makes the system
    /// tint the mark to match the menu bar theme.
    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIconTemplate") ?? NSImage()
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MixerView()
                .environment(engine)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
