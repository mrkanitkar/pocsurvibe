import CoreMIDI
import Foundation
import os

/// Metadata about a UMP-capable MIDI endpoint.
public struct UMPEndpointInfo: Sendable, Equatable {
    /// CoreMIDI endpoint reference.
    public let endpointRef: MIDIEndpointRef
    /// Endpoint display name.
    public let name: String
    /// Whether this endpoint supports MIDI 2.0 protocol natively.
    public let hasMIDI2Support: Bool
    /// Number of function blocks (MIDI 2.0 concept).
    public let functionBlockCount: Int
}

/// Discovers MIDI 2.0 capable endpoints using CoreMIDI properties.
///
/// Queries `kMIDIPropertyProtocolID` on each source endpoint to determine
/// MIDI 2.0 support. Available on iOS 26+ (no `#available` needed).
public enum UMPEndpointDiscovery {

    private static let logger = Logger.survibe(category: "UMPEndpointDiscovery")

    // MARK: - Public Methods

    /// Discover all MIDI source endpoints with MIDI 2.0 capability info.
    public static func discoverEndpoints() -> [UMPEndpointInfo] {
        let sourceCount = MIDIGetNumberOfSources()
        var endpoints: [UMPEndpointInfo] = []

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }

            let name = stringProperty(source, key: kMIDIPropertyName) ?? "Unknown"
            let hasMIDI2 = checkMIDI2Support(source)

            let info = UMPEndpointInfo(
                endpointRef: source,
                name: name,
                hasMIDI2Support: hasMIDI2,
                functionBlockCount: 0
            )
            endpoints.append(info)
        }

        logger.info("UMP discovery: \(endpoints.count) endpoints, \(endpoints.filter(\.hasMIDI2Support).count) with MIDI 2.0")
        return endpoints
    }

    /// Check if a specific endpoint supports MIDI 2.0.
    public static func supportsMIDI2(endpoint: MIDIEndpointRef) -> Bool {
        checkMIDI2Support(endpoint)
    }

    // MARK: - Private Helpers

    private static func checkMIDI2Support(_ endpoint: MIDIEndpointRef) -> Bool {
        var protocolID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyProtocolID, &protocolID)
        guard status == noErr else { return false }
        return protocolID == MIDIProtocolID._2_0.rawValue
    }

    private static func stringProperty(
        _ object: MIDIObjectRef,
        key: CFString
    ) -> String? {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, key, &value)
        guard status == noErr, let cfString = value?.takeRetainedValue() else { return nil }
        return cfString as String
    }
}
