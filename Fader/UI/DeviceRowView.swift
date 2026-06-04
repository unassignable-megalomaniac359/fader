import SwiftUI

/// One output device: transport icon, name, checkmark on the active one.
/// Clicking switches the system default output.
struct DeviceRowView: View {
    @Environment(MixerEngine.self) private var engine
    let device: AudioDevice

    @State private var isHovering = false

    private var isActive: Bool {
        engine.deviceMonitor.defaultDeviceID == device.id
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
                if isActive {
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
