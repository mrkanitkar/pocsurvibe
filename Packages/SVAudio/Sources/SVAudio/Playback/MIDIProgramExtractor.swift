// Packages/SVAudio/Sources/SVAudio/Playback/MIDIProgramExtractor.swift
import Foundation

/// Standard MIDI File parser — extracts the first Program Change event per
/// track. Used by `ProductionMultiChannelEngine.loadSong(.midi(...))` to
/// determine which SF2 programs to load into `samplers[1..N]` before binding
/// `sequencer.tracks[i].destinationAudioUnit`.
///
/// Returns `nil` for tracks with no Program Change event — caller defaults
/// to GM 0 (Acoustic Grand) in that case.
public enum MIDIProgramExtractor {

    /// Errors thrown by ``extractPrograms(midi:)``.
    public enum Error: Swift.Error, Equatable {
        /// The data does not begin with a valid `MThd` chunk marker.
        case missingHeader
        /// The data ended before all declared bytes could be read.
        case truncated
        /// A track chunk at the given index has an invalid `MTrk` marker.
        case malformedTrack(index: Int)
    }

    /// Parse Standard MIDI File bytes; return per-track first-program-change
    /// (`nil` for tracks with no PC).
    ///
    /// - Parameter data: Raw bytes of a Standard MIDI File (format 0, 1, or 2).
    /// - Returns: An array with one entry per track; entry is `nil` when the
    ///   track contains no Program Change event.
    /// - Throws: ``Error`` on structural problems (bad magic, truncation, etc.).
    public static func extractPrograms(midi data: Data) throws -> [UInt8?] {
        var cursor = 0

        // 1. Header chunk: 4-byte "MThd" + 4-byte length + 6-byte payload
        guard data.count >= 14 else { throw Error.truncated }
        guard data[0] == 0x4D, data[1] == 0x54, data[2] == 0x68, data[3] == 0x64 else {
            throw Error.missingHeader
        }
        cursor = 4
        let headerLen = readUInt32(data, at: cursor)
        cursor += 4
        guard cursor + Int(headerLen) <= data.count else { throw Error.truncated }
        // format (UInt16 at cursor), ntrks (UInt16 at cursor+2), division (UInt16 at cursor+4)
        let ntrks = Int(readUInt16(data, at: cursor + 2))
        cursor += Int(headerLen)

        var result: [UInt8?] = []
        for trackIndex in 0..<ntrks {
            // Each track: 4-byte "MTrk" + 4-byte length + payload
            guard cursor + 8 <= data.count else { throw Error.truncated }
            guard data[cursor] == 0x4D, data[cursor + 1] == 0x54,
                  data[cursor + 2] == 0x72, data[cursor + 3] == 0x6B else {
                throw Error.malformedTrack(index: trackIndex)
            }
            cursor += 4
            let trackLen = Int(readUInt32(data, at: cursor))
            cursor += 4
            guard cursor + trackLen <= data.count else { throw Error.truncated }
            let trackEnd = cursor + trackLen

            let firstPC = scanFirstProgramChange(data, range: cursor..<trackEnd)
            result.append(firstPC)

            cursor = trackEnd
        }

        return result
    }

    /// Walk events in `range` looking for the first Program Change (0xCn).
    private static func scanFirstProgramChange(_ data: Data, range: Range<Int>) -> UInt8? {
        var cursor = range.lowerBound
        var runningStatus: UInt8 = 0

        while cursor < range.upperBound {
            // Skip variable-length delta-time
            let (_, deltaConsumed) = readVLQ(data, at: cursor)
            cursor += deltaConsumed
            guard cursor < range.upperBound else { return nil }

            var status = data[cursor]
            if status < 0x80 {
                // running status — reuse last status; cursor stays on first data byte
                status = runningStatus
            } else {
                runningStatus = status
                cursor += 1
            }

            if status == 0xFF {
                // Meta event: type byte, then VLQ length, then data
                guard cursor < range.upperBound else { return nil }
                cursor += 1  // type byte
                let (metaLen, metaConsumed) = readVLQ(data, at: cursor)
                cursor += metaConsumed
                cursor += Int(metaLen)
            } else if status == 0xF0 || status == 0xF7 {
                // SysEx: VLQ length, then data
                let (sysLen, sysConsumed) = readVLQ(data, at: cursor)
                cursor += sysConsumed
                cursor += Int(sysLen)
            } else {
                let high = status & 0xF0
                switch high {
                case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
                    // Two data bytes
                    cursor += 2
                case 0xC0:
                    // Program Change — one data byte
                    guard cursor < range.upperBound else { return nil }
                    return data[cursor]
                case 0xD0:
                    // Channel pressure — one data byte
                    cursor += 1
                default:
                    return nil
                }
            }
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    /// Read a Standard MIDI File variable-length quantity. Returns (value, bytesConsumed).
    private static func readVLQ(_ data: Data, at offset: Int) -> (UInt32, Int) {
        var value: UInt32 = 0
        var consumed = 0
        var cursor = offset
        while cursor < data.count {
            let byte = data[cursor]
            value = (value << 7) | UInt32(byte & 0x7F)
            consumed += 1
            cursor += 1
            if byte < 0x80 { break }
        }
        return (value, consumed)
    }
}
