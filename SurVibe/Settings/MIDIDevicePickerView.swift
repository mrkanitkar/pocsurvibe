import SVAudio
import SwiftUI

/// Picker for choosing which connected MIDI device feeds the play-along session.
///
/// Lists every physical MIDI source currently exposed by `MIDIDeviceManager`,
/// annotated with USB/Bluetooth transport, source count, and a MIDI 2.0 badge
/// when the device's UMP endpoint discovery reports MIDI 2.0 support. Selection
/// persists across launches via the device's stable `MIDIUniqueID`.
///
/// The picker also offers a "Refresh" action that re-enumerates CoreMIDI — useful
/// when a keyboard is plugged in after the view has appeared.
struct MIDIDevicePickerView: View {

    // MARK: - State

    @State private var devices: [MIDIDeviceInfo] = []
    @State private var selectedID: Int32?

    private let deviceManager: MIDIDeviceManager

    // MARK: - Initialization

    init(deviceManager: MIDIDeviceManager = MIDIInputManager.shared.deviceManager) {
        self.deviceManager = deviceManager
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                if devices.isEmpty {
                    emptyState
                } else {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
            } header: {
                Text("Available devices")
            } footer: {
                Text(
                    "MIDI selection persists across launches. Connect a class-compliant USB "
                        + "keyboard or pair a Bluetooth MIDI device in iOS Settings to see it here."
                )
            }

            Section {
                Button {
                    refresh()
                } label: {
                    Label("Refresh device list", systemImage: "arrow.clockwise")
                }
                .accessibilityHint("Re-enumerate connected MIDI devices")
            }
        }
        .navigationTitle("MIDI Device")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            MIDIInputManager.shared.start()
            refresh()
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No MIDI devices connected", systemImage: "pianokeys")
                .font(.body)
            Text("Connect a USB or Bluetooth MIDI keyboard, then tap Refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func deviceRow(_ device: MIDIDeviceInfo) -> some View {
        Button {
            select(device)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: transportIcon(for: device))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: device.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if device.supportsMIDI2 {
                            midi2Badge
                        }
                    }
                    Text(subtitle(for: device))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if device.id == selectedID {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: device))
        .accessibilityHint(device.id == selectedID ? "Currently selected" : "Double tap to select this device")
    }

    /// Small pill marking a MIDI 2.0-capable endpoint.
    private var midi2Badge: some View {
        Text("MIDI 2.0")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Supports MIDI 2.0")
    }

    // MARK: - Helpers

    private func refresh() {
        deviceManager.refreshDevices()
        // `refreshDevices` writes to MainActor properties via `Task`. Read the
        // thread-safe snapshot directly so the picker reflects state immediately.
        devices = deviceManager.availableDevices
        selectedID = deviceManager.selectedDeviceID
    }

    private func select(_ device: MIDIDeviceInfo) {
        deviceManager.selectDevice(device)
        selectedID = device.id
    }

    private func transportIcon(for device: MIDIDeviceInfo) -> String {
        if device.isUSB { return "cable.connector" }
        if device.isBluetooth { return "wave.3.right" }
        return "pianokeys"
    }

    private func subtitle(for device: MIDIDeviceInfo) -> String {
        var parts: [String] = []
        if !device.manufacturer.isEmpty {
            parts.append(device.manufacturer)
        }
        if device.isUSB {
            parts.append("USB")
        } else if device.isBluetooth {
            parts.append("Bluetooth")
        }
        parts.append(device.sourceCount == 1 ? "1 source" : "\(device.sourceCount) sources")
        return parts.joined(separator: " • ")
    }

    private func accessibilityLabel(for device: MIDIDeviceInfo) -> String {
        var parts: [String] = [device.name]
        if device.supportsMIDI2 { parts.append("MIDI 2.0") }
        if device.isUSB { parts.append("USB") } else if device.isBluetooth { parts.append("Bluetooth") }
        if device.id == selectedID { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        MIDIDevicePickerView()
    }
}
