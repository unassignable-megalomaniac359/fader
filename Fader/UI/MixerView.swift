import SwiftUI

/// The menu bar popover: system output on top, per-app mixer below.
struct MixerView: View {
    @Environment(MixerEngine.self) private var engine

    /// Grip-drag state: which row is in flight and how far it travelled.
    @State private var draggedUID: String?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            outputSection

            if engine.isStarted, engine.deviceMonitor.devices.count > 1 || !disconnectedBluetooth.isEmpty {
                devicesSection
            }

            if engine.needsAudioCapturePermission {
                PermissionBanner()
            }

            Divider()

            appsSection

            Divider()

            FooterView()
        }
        .padding(12)
        .frame(width: 320)
    }

    /// "Disconnected" means absent from the HAL — that's what decides whether
    /// the device can play. IOBluetooth's own connection flag lags the HAL by
    /// seconds, which would leave a just-disconnected speaker in neither list.
    private var disconnectedBluetooth: [BluetoothAudioDevice] {
        engine.bluetooth.paired.filter { peer in
            !engine.deviceMonitor.devices.contains { $0.matches(bluetoothID: peer.id) }
        }
    }

    /// One priority-ordered list of present outputs (wired and connected
    /// Bluetooth alike) — drag the grip to set the order, which doubles as
    /// the auto-switch priority. Stale wired devices collapse into the
    /// "Rarely used" disclosure (also a drop target for demoting); paired-
    /// but-disconnected Bluetooth keeps its own section below and rejoins
    /// the main list at its ranked position when it connects.
    private var devicesSection: some View {
        let main = engine.deviceMonitor.devices.filter { !engine.deviceMonitor.isRarelyUsed($0) }
        let rarelyUsed = engine.deviceMonitor.devices.filter { engine.deviceMonitor.isRarelyUsed($0) }

        return VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(Array(main.enumerated()), id: \.element.id) { index, device in
                DeviceRowView(
                    device: device,
                    reorder: { event in handleReorder(event, index: index, main: main) },
                    suppressHover: draggedUID != nil && draggedUID != device.uid
                )
                .offset(y: rowOffset(index: index, main: main))
                .zIndex(draggedUID == device.uid ? 1 : 0)
                .animation(
                    draggedUID == device.uid ? nil : .easeOut(duration: 0.15),
                    value: rowOffset(index: index, main: main)
                )
            }
            if !rarelyUsed.isEmpty || draggedUID != nil {
                RarelyUsedDisclosure(devices: rarelyUsed, isDropTarget: isDemoteTargeted(main: main))
            }
            if !disconnectedBluetooth.isEmpty {
                Text("Bluetooth")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                ForEach(disconnectedBluetooth) { device in
                    BluetoothRowView(device: device)
                }
            }
        }
        .padding(.horizontal, -8)
        .task { engine.bluetooth.refresh() }
    }

    // MARK: - Grip-drag reordering

    private static let rowSpacing: CGFloat = 2
    /// Distance between row centers — the unit of drag math.
    private static let rowPitch: CGFloat = DeviceRowView.rowHeight + rowSpacing

    /// Slot the dragged row currently aims at; `main.count` is the demote
    /// slot (the "Rarely used" row right below the list), allowed only for
    /// devices that can actually be demoted.
    private func dragTarget(from: Int, main: [AudioDevice]) -> Int {
        let delta = Int((dragOffset / Self.rowPitch).rounded())
        let canDemote = !main[from].isBluetooth && engine.deviceMonitor.defaultDeviceID != main[from].id
        return min(max(from + delta, 0), canDemote ? main.count : main.count - 1)
    }

    private func rowOffset(index: Int, main: [AudioDevice]) -> CGFloat {
        guard let dragged = draggedUID,
              let from = main.firstIndex(where: { $0.uid == dragged })
        else { return 0 }
        if index == from { return dragOffset }
        let target = dragTarget(from: from, main: main)
        if index > from, index <= target { return -Self.rowPitch }
        if index < from, index >= target { return Self.rowPitch }
        return 0
    }

    private func isDemoteTargeted(main: [AudioDevice]) -> Bool {
        guard let dragged = draggedUID,
              let from = main.firstIndex(where: { $0.uid == dragged })
        else { return false }
        return dragTarget(from: from, main: main) == main.count
    }

    private func handleReorder(_ event: DeviceRowView.ReorderEvent, index: Int, main: [AudioDevice]) {
        switch event {
        case let .moved(translation):
            draggedUID = main[index].uid
            dragOffset = translation
        case .finished:
            defer {
                draggedUID = nil
                dragOffset = 0
            }
            guard main.indices.contains(index) else { return }
            let target = dragTarget(from: index, main: main)
            if target == main.count {
                engine.deviceMonitor.markRarelyUsed(main[index])
            } else if target != index {
                var order = main.map(\.uid)
                order.move(
                    fromOffsets: IndexSet(integer: index),
                    toOffset: target > index ? target + 1 : target
                )
                engine.deviceMonitor.applyOrder(order)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Output")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(engine.systemVolume.deviceName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ControlSlider(
                value: Binding(
                    get: { engine.systemVolume.volume },
                    set: { engine.systemVolume.setVolume($0) }
                ),
                icon: engine.systemVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                iconDimmed: engine.systemVolume.isMuted,
                onIconTap: { engine.systemVolume.toggleMute() }
            )
        }
    }

    /// Apps audible right now, plus silent ones the user has adjusted —
    /// hiding those would strand their saved volume.
    private var mixerApps: [AudioApp] {
        engine.processMonitor.apps.filter { $0.isPlaying || !engine.volume(for: $0).isNeutral }
    }

    @ViewBuilder
    private var appsSection: some View {
        if !engine.isStarted {
            HStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for the audio system…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 16)
        } else if mixerApps.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("Nothing is playing")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                Spacer()
            }
        } else {
            // MenuBarExtra windows size to the content's ideal height, and a
            // ScrollView's ideal height is zero — give it an explicit one.
            // rowHeight tracks AppRowView's layout: name line + slider + spacing.
            let rowHeight: CGFloat = 57
            let apps = mixerApps
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(apps) { app in
                        AppRowView(app: app)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: min(CGFloat(apps.count), 6) * rowHeight)
        }
    }
}

/// Shown when tap creation failed — almost always missing the
/// System Audio Recording permission.
struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio access needed")
                    .font(.system(size: 11, weight: .semibold))
                Text("Allow Fader to record system audio in Privacy & Security.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                if let settingsURL = URL(string: url) {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
