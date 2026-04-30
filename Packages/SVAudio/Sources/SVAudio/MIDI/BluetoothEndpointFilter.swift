import CoreMIDI
import Foundation

// MARK: - EndpointKind

/// Transport classification for a CoreMIDI endpoint.
///
/// Used to dispatch a connected MIDI source between fast paths (USB / virtual)
/// and the Practice-mode path (Bluetooth) where scoring is suppressed because
/// iOS's BLE 11.25 ms connection-interval floor makes timing untrustworthy.
public enum EndpointKind: String, Sendable, Hashable {
    case usb
    case virtual
    case bluetooth
    case network
    case unknown
}

// MARK: - EndpointDescriptor

/// Stable descriptor for a connected CoreMIDI endpoint.
///
/// `endpointID` is the `MIDIUniqueID` (CoreMIDI's persistent identifier) and is
/// the key consulted in the per-event scoring blocklist.
public struct EndpointDescriptor: Sendable, Hashable {

    /// CoreMIDI persistent identifier for the endpoint.
    public let endpointID: MIDIUniqueID

    /// Human-readable display name (e.g. "Yamaha PSR-400").
    public let displayName: String

    /// Detected transport classification.
    public let kind: EndpointKind

    /// Memberwise initializer.
    ///
    /// - Parameters:
    ///   - endpointID: CoreMIDI `MIDIUniqueID` for the endpoint.
    ///   - displayName: Human-readable name.
    ///   - kind: Detected transport classification.
    public init(endpointID: MIDIUniqueID, displayName: String, kind: EndpointKind) {
        self.endpointID = endpointID
        self.displayName = displayName
        self.kind = kind
    }
}

// MARK: - BluetoothEndpointFilter

/// Heuristic classification of a CoreMIDI endpoint by its `kMIDIPropertyDriverOwner`.
///
/// Apple does not expose a transport-property API on `MIDIEndpointRef`, so this
/// filter inspects the endpoint's driver-owner string. The matching logic is
/// split into two methods:
///
/// - ``detectKind(_:)`` reads `kMIDIPropertyDriverOwner` from a live endpoint.
/// - ``parseKind(driverOwner:)`` performs the pure string match — exposed
///   separately so unit tests can exercise the heuristic without a real CoreMIDI
///   endpoint.
///
/// The bluetooth match is intentionally broad (`bluetooth`, `btmidi`, `btle`)
/// because Apple's first-party driver historically reports as
/// `Apple BTLE MIDI Driver` while third-party drivers vary. False negatives
/// degrade to `.unknown` (events flow normally — scoring not suppressed); false
/// positives degrade to Practice mode (scoring suppressed but audio works).
public struct BluetoothEndpointFilter: Sendable {

    // MARK: - Live Detection

    /// Detect the transport kind of a live CoreMIDI endpoint.
    ///
    /// Reads `kMIDIPropertyDriverOwner` and forwards the value to
    /// ``parseKind(driverOwner:)``. Returns `.unknown` if the property is
    /// missing or the call fails.
    ///
    /// - Parameter endpoint: The CoreMIDI endpoint to inspect.
    /// - Returns: The detected ``EndpointKind``, or `.unknown` if the property
    ///   could not be read.
    public static func detectKind(_ endpoint: MIDIEndpointRef) -> EndpointKind {
        var driverOwner: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDriverOwner, &driverOwner)
        guard status == noErr, let owner = driverOwner?.takeRetainedValue() as String? else {
            return .unknown
        }
        return parseKind(driverOwner: owner)
    }

    // MARK: - Pure Parsing

    /// Classify a driver-owner string into an ``EndpointKind``.
    ///
    /// Pure (no CoreMIDI calls) so it is unit-testable. Matching is
    /// case-insensitive and substring-based; the order of checks is significant
    /// because some drivers contain multiple keywords (Bluetooth wins over USB).
    ///
    /// - Parameter driverOwner: Value of the `kMIDIPropertyDriverOwner`
    ///   property. May be empty.
    /// - Returns: The detected ``EndpointKind``. Empty or unrecognized strings
    ///   return `.unknown`.
    public static func parseKind(driverOwner: String) -> EndpointKind {
        let lower = driverOwner.lowercased()
        guard !lower.isEmpty else { return .unknown }
        if lower.contains("bluetooth") || lower.contains("btmidi") || lower.contains("btle") {
            return .bluetooth
        }
        if lower.contains("usb") { return .usb }
        if lower.contains("network") { return .network }
        if lower.contains("virtual") { return .virtual }
        return .unknown
    }
}
