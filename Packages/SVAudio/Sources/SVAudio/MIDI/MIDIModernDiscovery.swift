import CoreMIDI
import Foundation
import os.log

/// Dumps MIDI 2.0 runtime discovery state for every attached device.
///
/// Two independent iOS 18+ managers own this information:
/// - `MIDIUMPEndpointManager.shared.umpEndpoints` — UMP 1.1 endpoint discovery
///   (name, product instance, supported protocols, function blocks, device info).
/// - `MIDICIDeviceManager.shared.discoveredCIDevices` — MIDI-CI discovery
///   responses (profile configuration, property exchange, process inquiry).
///
/// A device that reports nothing in either manager is pure MIDI 1.0. This type
/// is `@MainActor` because both managers surface observable state on the main
/// actor per Apple's framework guidance.
@MainActor
public enum MIDIModernDiscovery {
    private static let logger = Logger.survibe(category: "MIDIModernDiscovery")

    /// Enumerate every UMP endpoint + MIDI-CI device currently visible and
    /// emit one tagged line per entry to the shared diag file.
    public static func dump() {
        dumpUMPEndpoints()
        dumpCIDevices()
    }

    private static func dumpUMPEndpoints() {
        let endpoints = MIDIUMPEndpointManager.shared.umpEndpoints
        if endpoints.isEmpty {
            write("[UMP] (none) — no MIDI 2.0 UMP endpoints discovered")
            return
        }
        for endpoint in endpoints {
            let info = endpoint.deviceInfo
            let blocks = endpoint.functionBlocks.map { String(describing: $0) }
                .joined(separator: " | ")
            let msg = """
                [UMP] name='\(endpoint.name)' \
                productInstanceID='\(endpoint.productInstanceID)' \
                midiProtocol=\(String(describing: endpoint.midiProtocol)) \
                supportedMIDIProtocols=\(String(describing: endpoint.supportedMIDIProtocols)) \
                manufacturerID=\(String(describing: info.manufacturerID)) \
                family=\(String(describing: info.family)) \
                modelNumber=\(String(describing: info.modelNumber)) \
                revisionLevel=\(String(describing: info.revisionLevel)) \
                hasStaticFunctionBlocks=\(endpoint.hasStaticFunctionBlocks) \
                functionBlockCount=\(endpoint.functionBlocks.count) \
                blocks=[\(blocks)]
                """
            write(msg)
        }
    }

    private static func dumpCIDevices() {
        let devices = MIDICIDeviceManager.shared.discoveredCIDevices
        if devices.isEmpty {
            write("[CI] (none) — no MIDI-CI responses received (device is MIDI 1.0 only)")
            return
        }
        for device in devices {
            let info = device.deviceInfo
            let profiles = device.profiles.map { String(describing: $0) }
                .joined(separator: ",")
            let msg = """
                [CI] muid=0x\(String(format: "%08X", device.muid)) \
                manufacturerID=\(String(describing: info.manufacturerID)) \
                family=\(String(describing: info.family)) \
                modelNumber=\(String(describing: info.modelNumber)) \
                revisionLevel=\(String(describing: info.revisionLevel)) \
                maxSysExSize=\(device.maxSysExSize) \
                maxPropExchReqs=\(device.maxPropertyExchangeRequests) \
                supportsProtocolNegotiation=\(device.supportsProtocolNegotiation) \
                supportsProfileConfiguration=\(device.supportsProfileConfiguration) \
                supportsPropertyExchange=\(device.supportsPropertyExchange) \
                supportsProcessInquiry=\(device.supportsProcessInquiry) \
                profiles=[\(profiles)]
                """
            write(msg)
        }
    }

    private static func write(_ line: String) {
        logger.info("\(line, privacy: .public)")
        MIDIDiagBridge.recordLine(line)
    }
}
