import CoreMIDI
import Foundation
import os
import Synchronization

/// Enumerates connected MIDI devices and manages device selection.
///
/// Thread-safe via `Mutex<DeviceState>`. UI-facing properties are updated
/// on `@MainActor` via `Task`. Selection persists to UserDefaults keyed
/// by `MIDIUniqueID` so reconnecting the same keyboard restores the choice.
///
/// ## Auto-Selection Heuristic
///
/// When no explicit selection exists, ranks devices by:
/// 1. USB over Bluetooth (lower latency)
/// 2. Previously-selected device (from UserDefaults)
/// 3. Most sources (more capable device)
/// 4. MIDI 2.0 support (when available from Phase 3)
public final class MIDIDeviceManager: Sendable {

    // MARK: - State

    struct DeviceState: Sendable {
        var availableDevices: [MIDIDeviceInfo] = []
        var selectedDeviceID: Int32?
    }

    private let state = Mutex<DeviceState>(DeviceState())

    private static let logger = Logger.survibe(category: "MIDIDeviceManager")
    private static let selectedDeviceKey = "midi_selected_device_id"

    // MARK: - MainActor Published Properties

    /// Names of all available physical MIDI devices for UI display.
    @MainActor public private(set) var availableDeviceNames: [String] = []

    /// Name of the currently selected device, or nil if none.
    @MainActor public private(set) var selectedDeviceName: String?

    // MARK: - Initialization

    /// Create a new device manager.
    ///
    /// Loads the previously-selected device ID from UserDefaults.
    public init() {
        let savedID = UserDefaults.standard.integer(forKey: Self.selectedDeviceKey)
        if savedID != 0 {
            state.withLock { $0.selectedDeviceID = Int32(savedID) }
        }
    }

    // MARK: - Device Enumeration

    /// Enumerate all connected physical MIDI devices.
    ///
    /// Queries CoreMIDI for device properties and builds a filtered list
    /// excluding virtual/IAC/network sources. Safe to call from any thread.
    public func refreshDevices() {
        let deviceCount = MIDIGetNumberOfDevices()
        var devices: [MIDIDeviceInfo] = []

        for i in 0..<deviceCount {
            let device = MIDIGetDevice(i)
            guard device != 0 else { continue }

            let entityCount = MIDIDeviceGetNumberOfEntities(device)
            var totalSources = 0
            var firstEndpoint: MIDIEndpointRef = 0

            for j in 0..<entityCount {
                let entity = MIDIDeviceGetEntity(device, j)
                let srcCount = MIDIEntityGetNumberOfSources(entity)
                totalSources += srcCount
                if firstEndpoint == 0, srcCount > 0 {
                    firstEndpoint = MIDIEntityGetSource(entity, 0)
                }
            }

            guard totalSources > 0, firstEndpoint != 0 else { continue }

            let name = Self.stringProperty(device, key: kMIDIPropertyName) ?? "Unknown"
            let manufacturer = Self.stringProperty(device, key: kMIDIPropertyManufacturer) ?? ""
            let driverOwner = Self.stringProperty(device, key: kMIDIPropertyDriverOwner) ?? ""

            // Filter out virtual and network sources
            let isVirtual = driverOwner.contains("com.apple.AppleMIDICenter")
                || driverOwner.contains("IAC")
                || name.contains("IAC Driver")
                || name.contains("Network Session")
            guard !isVirtual else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(device, kMIDIPropertyUniqueID, &uniqueID)

            let isUSB = driverOwner.contains("USB") || driverOwner.contains("AppleUSBMIDI")
            let isBluetooth = driverOwner.contains("Bluetooth") || driverOwner.contains("BLE")

            let info = MIDIDeviceInfo(
                id: uniqueID,
                endpointRef: firstEndpoint,
                name: name,
                manufacturer: manufacturer,
                isUSB: isUSB,
                isBluetooth: isBluetooth,
                supportsMIDI2: false,
                sourceCount: totalSources
            )
            devices.append(info)
        }

        // Enrich MIDI 2.0 support from UMP endpoint discovery
        let umpEndpoints = UMPEndpointDiscovery.discoverEndpoints()
        let midi2Endpoints = Set(umpEndpoints.filter(\.hasMIDI2Support).map(\.endpointRef))

        devices = devices.map { device in
            let hasMIDI2 = midi2Endpoints.contains(device.endpointRef)
            guard hasMIDI2 != device.supportsMIDI2 else { return device }
            return MIDIDeviceInfo(
                id: device.id,
                endpointRef: device.endpointRef,
                name: device.name,
                manufacturer: device.manufacturer,
                isUSB: device.isUSB,
                isBluetooth: device.isBluetooth,
                supportsMIDI2: hasMIDI2,
                sourceCount: device.sourceCount
            )
        }

        state.withLock { $0.availableDevices = devices }

        let names = devices.map(\.name)
        let selectedID = state.withLock { $0.selectedDeviceID }
        let selectedName = devices.first { $0.id == selectedID }?.name

        Task { @MainActor [weak self] in
            self?.availableDeviceNames = names
            self?.selectedDeviceName = selectedName
        }

        Self.logger.info("Refreshed devices: \(devices.count) found")
    }

    // MARK: - Selection

    /// Auto-select the best available device.
    ///
    /// Ranking: previously-selected > USB > Bluetooth > most sources.
    ///
    /// - Returns: The selected device, or nil if no devices available.
    public func autoSelectBestDevice() -> MIDIDeviceInfo? {
        state.withLock { s in
            guard !s.availableDevices.isEmpty else { return nil }

            // Prefer previously-selected device if still available
            if let savedID = s.selectedDeviceID,
               let saved = s.availableDevices.first(where: { $0.id == savedID }) {
                return saved
            }

            // Rank: USB > BT > other, then by source count
            let ranked = s.availableDevices.sorted { a, b in
                if a.isUSB != b.isUSB { return a.isUSB }
                if a.supportsMIDI2 != b.supportsMIDI2 { return a.supportsMIDI2 }
                if a.isBluetooth != b.isBluetooth { return !a.isBluetooth }
                return a.sourceCount > b.sourceCount
            }

            let best = ranked.first
            if let best {
                s.selectedDeviceID = best.id
            }
            return best
        }
    }

    /// Explicitly select a device. Persists to UserDefaults.
    ///
    /// - Parameter device: The device to select.
    public func selectDevice(_ device: MIDIDeviceInfo) {
        state.withLock { $0.selectedDeviceID = device.id }
        UserDefaults.standard.set(Int(device.id), forKey: Self.selectedDeviceKey)

        Task { @MainActor [weak self] in
            self?.selectedDeviceName = device.name
        }

        Self.logger.info("Selected device: \(device.name, privacy: .public) (ID: \(device.id))")
    }

    /// Select a device by name.
    ///
    /// - Parameter name: The device display name to select.
    public func selectDevice(named name: String) {
        let device = state.withLock { s in
            s.availableDevices.first { $0.name == name }
        }
        if let device {
            selectDevice(device)
        }
    }

    /// Get the source endpoints for the currently selected device.
    ///
    /// - Returns: Array of CoreMIDI endpoint refs, or empty if no selection.
    public func selectedSourceEndpoints() -> [MIDIEndpointRef] {
        state.withLock { s in
            guard let id = s.selectedDeviceID,
                  let device = s.availableDevices.first(where: { $0.id == id }) else {
                return []
            }

            // Collect all source endpoints from the device's entities
            var endpoints: [MIDIEndpointRef] = []

            let deviceCount = MIDIGetNumberOfDevices()
            for i in 0..<deviceCount {
                let dev = MIDIGetDevice(i)
                var devID: Int32 = 0
                MIDIObjectGetIntegerProperty(dev, kMIDIPropertyUniqueID, &devID)
                guard devID == id else { continue }

                let entityCount = MIDIDeviceGetNumberOfEntities(dev)
                for j in 0..<entityCount {
                    let entity = MIDIDeviceGetEntity(dev, j)
                    let srcCount = MIDIEntityGetNumberOfSources(entity)
                    for k in 0..<srcCount {
                        endpoints.append(MIDIEntityGetSource(entity, k))
                    }
                }
                break
            }

            return endpoints.isEmpty ? [device.endpointRef] : endpoints
        }
    }

    /// All available devices.
    public var availableDevices: [MIDIDeviceInfo] {
        state.withLock { $0.availableDevices }
    }

    /// The currently selected device's MIDIUniqueID, or nil if no selection.
    public var selectedDeviceID: Int32? {
        state.withLock { $0.selectedDeviceID }
    }

    // MARK: - Private Helpers

    /// Read a string property from a CoreMIDI object.
    nonisolated private static func stringProperty(
        _ object: MIDIObjectRef,
        key: CFString
    ) -> String? {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, key, &value)
        guard status == noErr, let cfString = value?.takeRetainedValue() else { return nil }
        return cfString as String
    }
}
