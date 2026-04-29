import Foundation

/// Serialises a take to a Standard MIDI File (SMF) Type-0 byte stream.
///
/// PPQ = 1000. Tempo meta event `FF 51 03 0F 42 40` (60 BPM = 1,000,000 µs/qn)
/// makes 1 tick == 1 millisecond, so wall-clock timings round-trip exactly
/// regardless of the consumer's tempo interpretation. Without the explicit
/// tempo meta, SMF importers default to 120 BPM and double-time the file.
public enum MIDISerializer {

    /// Serialises notes + sustain events to a Standard MIDI File Type-0 byte stream.
    ///
    /// Emits a single track containing: tempo meta (60 BPM), program change at
    /// time 0, then chronologically-sorted note-on/note-off and CC64 sustain
    /// events, terminated by an end-of-track meta event.
    ///
    /// - Parameters:
    ///   - notes: Recorded notes; each emits a note-on at `onTimeSec` and
    ///     a note-off at `offTimeSec`.
    ///   - sustain: CC64 events; each emits a CC 64 message with value 0x7F
    ///     (down) or 0x00 (up).
    ///   - program: General MIDI program number (0–127) for the program-change
    ///     event at time 0 on channel 0.
    /// - Returns: A complete SMF Type-0 byte stream (header + single track).
    public static func serializeType0(
        notes: [RecordedNote],
        sustain: [RecordedSustainEvent],
        program: UInt8
    ) -> Data {
        var track = Data()
        // Tempo meta at delta 0.
        appendVarLen(&track, 0)
        track.append(contentsOf: [0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40])
        // Program change at delta 0.
        appendVarLen(&track, 0)
        track.append(contentsOf: [0xC0, program & 0x7F])

        struct Event { let tick: UInt64; let bytes: [UInt8] }
        var events: [Event] = []
        for n in notes {
            let velocity: UInt8 = max(1, n.velocity & 0x7F)
            events.append(Event(tick: secondsToTicks(n.onTimeSec),
                                bytes: [0x90, n.midi & 0x7F, velocity]))
            events.append(Event(tick: secondsToTicks(n.offTimeSec),
                                bytes: [0x80, n.midi & 0x7F, 0x40]))
        }
        for s in sustain {
            events.append(Event(tick: secondsToTicks(s.timeSec),
                                bytes: [0xB0 | (s.channel & 0x0F), 0x40, s.down ? 0x7F : 0x00]))
        }
        events.sort { $0.tick < $1.tick }

        var lastTick: UInt64 = 0
        for ev in events {
            appendVarLen(&track, UInt32(ev.tick - lastTick))
            track.append(contentsOf: ev.bytes)
            lastTick = ev.tick
        }
        // End-of-track meta.
        appendVarLen(&track, 0)
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        // Header chunk.
        var out = Data()
        out.append(contentsOf: [0x4D, 0x54, 0x68, 0x64])                                // "MThd"
        out.append(contentsOf: bigEndianBytes(UInt32(6)))                               // chunk len
        out.append(contentsOf: [0x00, 0x00])                                            // format 0
        out.append(contentsOf: [0x00, 0x01])                                            // 1 track
        out.append(contentsOf: [0x03, 0xE8])                                            // division = 1000

        // Track chunk.
        out.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])                                // "MTrk"
        out.append(contentsOf: bigEndianBytes(UInt32(track.count)))
        out.append(track)
        return out
    }

    /// Converts wall-clock seconds to ticks. PPQ 1000 + 60 BPM ⇒ 1 tick = 1 ms.
    private static func secondsToTicks(_ s: TimeInterval) -> UInt64 {
        UInt64(max(0, (s * 1000.0).rounded()))
    }

    /// Appends a MIDI variable-length quantity (7 bits per byte, MSB = continuation flag).
    private static func appendVarLen(_ data: inout Data, _ value: UInt32) {
        var v = value
        var buf: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            buf.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        data.append(contentsOf: buf)
    }

    /// Encodes a `UInt32` as 4 big-endian bytes.
    private static func bigEndianBytes(_ x: UInt32) -> [UInt8] {
        [UInt8((x >> 24) & 0xFF), UInt8((x >> 16) & 0xFF), UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF)]
    }
}
