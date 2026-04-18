import CoreMIDI
import Foundation
import os

/// Handles System Exclusive and Data 128-bit UMP messages.
///
/// Parses UMP message types 0x3 (64-bit SysEx) and 0x5 (128-bit data)
/// for future Property Exchange support. Currently logs and forwards
/// complete SysEx messages to registered handlers.
public final class SysExHandler: Sendable {

    /// A complete SysEx message reassembled from UMP packets.
    public struct SysExMessage: Sendable {
        /// Raw SysEx data bytes (excluding F0/F7 framing).
        public let data: [UInt8]
        /// Hardware timestamp of the first packet.
        public let timestamp: MIDITimeStamp
    }

    /// Create a new SysEx handler.
    public init() {}

    private let handlerLock = OSAllocatedUnfairLock<(@Sendable (SysExMessage) -> Void)?>(
        initialState: nil
    )

    private static let logger = Logger.survibe(category: "SysExHandler")

    /// Register a handler for complete SysEx messages.
    public var onSysEx: (@Sendable (SysExMessage) -> Void)? {
        get { handlerLock.withLock { $0 } }
        set { handlerLock.withLock { $0 = newValue } }
    }

    /// Process a 64-bit SysEx UMP packet (type 0x3).
    public func processSysEx64(word1: UInt32, word2: UInt32, timestamp: MIDITimeStamp) {
        let statusNibble = (word1 >> 20) & 0x0F
        let byteCount = Int((word1 >> 16) & 0x0F)

        var bytes: [UInt8] = []
        if byteCount >= 1 { bytes.append(UInt8((word1 >> 8) & 0xFF)) }
        if byteCount >= 2 { bytes.append(UInt8(word1 & 0xFF)) }
        if byteCount >= 3 { bytes.append(UInt8((word2 >> 24) & 0xFF)) }
        if byteCount >= 4 { bytes.append(UInt8((word2 >> 16) & 0xFF)) }
        if byteCount >= 5 { bytes.append(UInt8((word2 >> 8) & 0xFF)) }
        if byteCount >= 6 { bytes.append(UInt8(word2 & 0xFF)) }

        // Complete in one packet (status 0x0) or end of multi-packet (status 0x3)
        if statusNibble == 0x0 || statusNibble == 0x3 {
            let message = SysExMessage(data: bytes, timestamp: timestamp)
            handlerLock.withLock { $0?(message) }
        }

        Self.logger.debug("SysEx64: status=\(statusNibble), bytes=\(byteCount)")
    }

    /// Process a 128-bit Data UMP packet (type 0x5).
    public func processData128(words: [UInt32], timestamp: MIDITimeStamp) {
        guard words.count >= 4 else { return }
        Self.logger.debug("Data128 packet received: \(words.count) words")
        // Future: reassemble multi-packet data for Property Exchange
    }
}
