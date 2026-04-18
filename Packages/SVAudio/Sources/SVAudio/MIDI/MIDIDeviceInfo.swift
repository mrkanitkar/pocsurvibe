import CoreMIDI
import Foundation

/// Metadata about a connected MIDI device for device picker and auto-selection.
///
/// Populated from CoreMIDI property queries during device enumeration.
/// The `id` field is the device's `MIDIUniqueID`, which persists across
/// reconnections for UserDefaults-based selection memory.
public struct MIDIDeviceInfo: Sendable, Identifiable, Equatable, Hashable {

    // MARK: - Properties

    /// Stable unique identifier from CoreMIDI (persists across reconnections).
    public let id: Int32

    /// CoreMIDI endpoint reference for this device's primary source.
    public let endpointRef: MIDIEndpointRef

    /// Human-readable device name from kMIDIPropertyName.
    public let name: String

    /// Device manufacturer from kMIDIPropertyManufacturer.
    public let manufacturer: String

    /// Whether the device is connected via USB (lower latency than Bluetooth).
    public let isUSB: Bool

    /// Whether the device is connected via Bluetooth MIDI.
    public let isBluetooth: Bool

    /// Whether the device supports MIDI 2.0 natively (populated by UMP endpoint discovery in Phase 3).
    public let supportsMIDI2: Bool

    /// Number of MIDI sources this device exposes.
    public let sourceCount: Int

    // MARK: - Initialization

    /// Create a MIDI device info record.
    ///
    /// - Parameters:
    ///   - id: MIDIUniqueID for persistent identification.
    ///   - endpointRef: CoreMIDI endpoint reference.
    ///   - name: Device display name.
    ///   - manufacturer: Device manufacturer name.
    ///   - isUSB: Whether connected via USB.
    ///   - isBluetooth: Whether connected via Bluetooth.
    ///   - supportsMIDI2: Whether device supports MIDI 2.0 (default false, enriched in Phase 3).
    ///   - sourceCount: Number of MIDI sources on this device.
    public init(
        id: Int32,
        endpointRef: MIDIEndpointRef = 0,
        name: String,
        manufacturer: String = "",
        isUSB: Bool = false,
        isBluetooth: Bool = false,
        supportsMIDI2: Bool = false,
        sourceCount: Int = 1
    ) {
        self.id = id
        self.endpointRef = endpointRef
        self.name = name
        self.manufacturer = manufacturer
        self.isUSB = isUSB
        self.isBluetooth = isBluetooth
        self.supportsMIDI2 = supportsMIDI2
        self.sourceCount = sourceCount
    }

    // MARK: - Hashable

    /// Hash based on stable unique ID only.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable

    /// Equality based on stable unique ID.
    public static func == (lhs: MIDIDeviceInfo, rhs: MIDIDeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}
