import SwiftUI

/// One output device: transport icon, name, checkmark on the active one.
/// Clicking switches the system default output. Bluetooth devices get a
/// disconnect button on hover.
struct DeviceRowView: View {
    @Environment(MixerEngine.self) private var engine
    let device: AudioDevice

    @State private var isHovering = false

    private var isActive: Bool {
        engine.deviceMonitor.defaultDeviceID == device.id
    }

    private var bluetoothPeer: BluetoothAudioDevice? {
        engine.bluetooth.paired.first { device.matches(bluetoothID: $0.id) }
    }

    var body: some View {
        Button {
            engine.deviceMonitor.setDefault(device)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 18)
                Text(device.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if let peer = bluetoothPeer, isHovering {
                    Button {
                        engine.bluetooth.disconnect(peer)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect")
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                isHovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Wired devices that haven't been the output lately, folded behind one row.
/// Expanding is per-popover-open state; selecting a device stamps it used and
/// promotes it to the main list.
struct RarelyUsedDisclosure: View {
    let devices: [AudioDevice]

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                Text("Rarely used (\(devices.count))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                isHovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }

        if isExpanded {
            ForEach(devices) { device in
                DeviceRowView(device: device)
            }
        }
    }
}

/// A paired Bluetooth audio device that is not connected: dimmed row,
/// clicking connects and routes audio to it.
struct BluetoothRowView: View {
    @Environment(MixerEngine.self) private var engine
    let device: BluetoothAudioDevice

    @State private var isHovering = false

    private var isBusy: Bool {
        engine.bluetooth.busy.contains(device.id)
    }

    var body: some View {
        Button {
            engine.connectBluetooth(device)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                Text(device.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else if isHovering {
                    Text("Connect")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                isHovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(isBusy)
    }
}
