import CoreMIDI
import Foundation
import os

private let parserLogger = Logger.survibe(category: "FluidSynthMIDIParser")

/// Parses MIDI bytes (typically arriving from CoreMIDI's `MIDIPacketList`)
/// into `RealtimeMIDIEvent`s posted onto a `FluidSynthMIDIEventRing` for the
/// FluidSynth render block to drain.
///
/// Handles:
/// - Channel-voice events (0x80–0xEF) with their correct 1- or 2-byte payload
/// - Sysex (0xF0 ... 0xF7) — skipped
/// - System common (0xF1–0xF6) — skipped
/// - Real-time (0xF8–0xFF) — skipped
/// - Running status (chained events sharing a previous status byte)
///
/// **Note**: this parser does NOT handle SMF meta events (0xFF in SMF
/// context); CoreMIDI delivers raw stream bytes, not SMF.
public final class FluidSynthMIDIParser: @unchecked Sendable {

    private let ring: FluidSynthMIDIEventRing

    /// Create a parser that posts decoded events to the given ring.
    public init(ring: FluidSynthMIDIEventRing) {
        self.ring = ring
    }

    /// Parse a raw byte stream and post events to the ring with the given
    /// host-time timestamp.
    public func parseRawBytes(_ bytes: [UInt8], timestamp: UInt64) {
        var i = 0
        var runningStatus: UInt8 = 0
        let n = bytes.count
        while i < n {
            var status = bytes[i]
            if status & 0x80 != 0 {
                // New status byte
                if status >= 0xF8 {
                    // Real-time — single-byte event, skip
                    i += 1
                    continue
                }
                if status == 0xF0 {
                    // Sysex: skip until 0xF7
                    i += 1
                    while i < n, bytes[i] != 0xF7 { i += 1 }
                    if i < n { i += 1 }  // skip the 0xF7 itself
                    continue
                }
                if status >= 0xF1 && status <= 0xF7 {
                    // System common — skip with payload. A stray 0xF7 outside
                    // a sysex block (or 0xF4/0xF5 undefined statuses) clears
                    // running status to prevent it being reused after a
                    // malformed sequence.
                    i += 1
                    if status == 0xF1 || status == 0xF3 { i += 1 }       // 1 data byte
                    else if status == 0xF2 { i += 2 }                     // 2 data bytes
                    runningStatus = 0
                    continue
                }
                // Channel voice
                runningStatus = status
                i += 1
            } else {
                // Running status — reuse last channel-voice status
                if runningStatus < 0x80 || runningStatus >= 0xF0 {
                    // Stream malformed — bail
                    break
                }
                status = runningStatus
            }

            let high = status & 0xF0
            let channel = status & 0x0F
            switch high {
            case 0xC0, 0xD0:
                // Program change / channel pressure: 1 data byte
                guard i < n else { break }
                let d1 = bytes[i]; i += 1
                _ = ring.enqueue(RealtimeMIDIEvent(
                    timestamp: timestamp, channel: channel,
                    status: status, data1: d1, data2: 0
                ))
            default:
                // Note off / on / poly pressure / CC / pitch bend: 2 data bytes
                guard i + 1 < n else { break }
                let d1 = bytes[i]; i += 1
                let d2 = bytes[i]; i += 1
                _ = ring.enqueue(RealtimeMIDIEvent(
                    timestamp: timestamp, channel: channel,
                    status: status, data1: d1, data2: d2
                ))
            }
        }
    }

    /// CoreMIDI receive callback adapter — call this from your
    /// `MIDIDestinationCreate` callback after extracting `MIDIPacketList`.
    ///
    /// - Parameter packetList: The packet list delivered by CoreMIDI. The
    ///   pointee is read on the calling thread and not retained.
    public func parsePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        let count = Int(packetList.pointee.numPackets)
        var packet = packetList.pointee.packet
        for i in 0..<count {
            withUnsafePointer(to: packet.data) { tuplePtr in
                let bytePtr = UnsafeRawPointer(tuplePtr).assumingMemoryBound(to: UInt8.self)
                let buffer = UnsafeBufferPointer(start: bytePtr, count: Int(packet.length))
                parseRawBytes(Array(buffer), timestamp: packet.timeStamp)
            }
            // Advancing past the LAST packet would deref past the end of the
            // packet-list buffer (UB). Only advance when more packets remain.
            if i < count - 1 {
                packet = MIDIPacketNext(&packet).pointee
            }
        }
    }
}
