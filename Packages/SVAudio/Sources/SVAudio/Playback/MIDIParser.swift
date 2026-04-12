import Foundation
import os.log

/// Parses Standard MIDI File (SMF) data into an array of MIDIEvent objects.
///
/// Supports SMF format 0 (single track) and format 1 (multiple simultaneous tracks).
/// Format 2 (independent patterns) returns `.unsupportedFormat` error.
///
/// ## Usage
/// ```swift
/// let result = MIDIParser.parse(data: song.midiData)
/// switch result {
/// case .success(let events): // schedule events
/// case .failure(let error): // handle error
/// }
/// ```
///
/// ## Timing
/// Delta-time ticks are converted to absolute seconds using the file's
/// time division (ticks per quarter note) and tempo meta events.
/// Default tempo is 120 BPM if no tempo event is present.
public struct MIDIParser: Sendable {
    private static let logger = Logger.survibe(category: "MIDIParser")

    // MARK: - Public Interface

    /// Parse MIDI data into an array of note events.
    ///
    /// - Parameter data: Raw binary MIDI file data (Standard MIDI File format).
    ///   Returns `.failure(.invalidHeader)` if nil or too short.
    /// - Returns: A Result containing sorted MIDIEvent array on success,
    ///   or MIDIParseError on failure.
    public static func parse(
        data: Data?
    ) -> Result<[MIDIEvent], MIDIParseError> {
        guard let data, data.count >= 14 else {
            logger.error("MIDI parse failed: data is nil or too short")
            return .failure(.invalidHeader)
        }

        let headerResult = parseHeader(data: data)
        guard case .success(let header) = headerResult else {
            if case .failure(let error) = headerResult {
                return .failure(error)
            }
            return .failure(.invalidHeader)
        }

        let trackResult = parseTracks(data: data, header: header)
        guard case .success(let trackData) = trackResult else {
            if case .failure(let error) = trackResult {
                return .failure(error)
            }
            return .failure(.corruptedData)
        }

        let events = pairNoteEvents(
            noteOns: trackData.noteOns,
            noteOffs: trackData.noteOffs,
            tempoChanges: trackData.tempoChanges,
            ticksPerQuarterNote: header.ticksPerQuarterNote
        )

        guard !events.isEmpty else {
            logger.warning("MIDI parse complete but no note events found")
            return .failure(.noNotesFound)
        }

        let lastTimestamp = events.last?.timestamp ?? 0
        logger.info("Parsed \(events.count) MIDI events, duration: \(String(format: "%.1f", lastTimestamp), privacy: .public)s")
        return .success(events)
    }
}

// MARK: - Header Parsing

private extension MIDIParser {

    /// Parsed MIDI file header information.
    struct MIDIHeader {
        let format: UInt16
        let trackCount: UInt16
        let ticksPerQuarterNote: Int
        let dataOffset: Int
    }

    /// Validates and parses the MThd header chunk.
    static func parseHeader(
        data: Data
    ) -> Result<MIDIHeader, MIDIParseError> {
        let headerBytes = [UInt8](data[0..<4])
        guard headerBytes == [0x4D, 0x54, 0x68, 0x64] else {
            logger.error("Invalid header magic bytes")
            return .failure(.invalidHeader)
        }

        var reader = MIDIDataReader(data: data, position: 4)

        let headerLength = reader.readUInt32BE()
        guard headerLength >= 6 else {
            return .failure(.invalidHeader)
        }

        let format = reader.readUInt16BE()
        guard format <= 1 else {
            logger.warning("MIDI format 2 not supported")
            return .failure(.unsupportedFormat)
        }

        let trackCount = reader.readUInt16BE()
        let division = reader.readUInt16BE()
        guard division > 0, (division & 0x8000) == 0 else {
            logger.error("SMPTE time division not supported")
            return .failure(.corruptedData)
        }

        logger.info("MIDI header: format=\(format), tracks=\(trackCount), division=\(division)")

        return .success(MIDIHeader(
            format: format,
            trackCount: trackCount,
            ticksPerQuarterNote: Int(division),
            dataOffset: 8 + Int(headerLength)
        ))
    }
}

// MARK: - Track Parsing

private extension MIDIParser {

    /// Note-on data collected during track parsing.
    struct NoteOnRecord {
        let noteNumber: UInt8
        let velocity: UInt8
        let absoluteTick: Int
        let channel: UInt8
    }

    /// Note-off data collected during track parsing.
    struct NoteOffRecord {
        let noteNumber: UInt8
        let absoluteTick: Int
        let channel: UInt8
    }

    /// Tempo change data collected during track parsing.
    struct TempoChange {
        let tick: Int
        let microsecondsPerBeat: Int
    }

    /// Aggregated data from all parsed tracks.
    struct ParsedTrackData {
        var noteOns: [NoteOnRecord]
        var noteOffs: [NoteOffRecord]
        var tempoChanges: [TempoChange]
    }

    /// Parses all MTrk track chunks from the MIDI data.
    static func parseTracks(
        data: Data,
        header: MIDIHeader
    ) -> Result<ParsedTrackData, MIDIParseError> {
        var reader = MIDIDataReader(
            data: data,
            position: header.dataOffset
        )
        var trackData = ParsedTrackData(
            noteOns: [],
            noteOffs: [],
            tempoChanges: []
        )

        for trackIndex in 0..<Int(header.trackCount) {
            guard reader.position + 8 <= data.count else { break }

            let trackHeader = reader.readBytes(4)
            guard trackHeader == [0x4D, 0x54, 0x72, 0x6B] else {
                logger.warning("Track \(trackIndex): missing MTrk at position \(reader.position - 4)")
                return .failure(.corruptedData)
            }

            let trackLength = Int(reader.readUInt32BE())
            let trackEnd = reader.position + trackLength

            parseTrackEvents(
                reader: &reader,
                trackEnd: trackEnd,
                dataCount: data.count,
                trackData: &trackData
            )

            reader.position = min(trackEnd, data.count)
        }

        return .success(trackData)
    }

    /// Parses events within a single MTrk chunk.
    static func parseTrackEvents(
        reader: inout MIDIDataReader,
        trackEnd: Int,
        dataCount: Int,
        trackData: inout ParsedTrackData
    ) {
        var absoluteTick = 0
        var runningStatus: UInt8 = 0

        while reader.position < trackEnd,
              reader.position < dataCount {
            let delta = reader.readVariableLength()
            absoluteTick += delta

            guard reader.position < dataCount else { break }
            var statusByte = reader.readByte()

            if (statusByte & 0x80) == 0 {
                reader.position -= 1
                statusByte = runningStatus
            } else if statusByte < 0xF0 {
                runningStatus = statusByte
            }

            dispatchMessage(
                statusByte: statusByte,
                absoluteTick: absoluteTick,
                reader: &reader,
                trackData: &trackData
            )
        }
    }

    /// Dispatches parsing based on the MIDI status byte message type.
    static func dispatchMessage(
        statusByte: UInt8,
        absoluteTick: Int,
        reader: inout MIDIDataReader,
        trackData: inout ParsedTrackData
    ) {
        let messageType = statusByte & 0xF0
        let channel = statusByte & 0x0F

        switch messageType {
        case 0x90:
            handleNoteOn(
                channel: channel, tick: absoluteTick,
                reader: &reader, trackData: &trackData
            )
        case 0x80:
            handleNoteOff(
                channel: channel, tick: absoluteTick,
                reader: &reader, trackData: &trackData
            )
        case 0xA0, 0xB0, 0xE0:
            _ = reader.readByte()
            _ = reader.readByte()
        case 0xC0, 0xD0:
            _ = reader.readByte()
        case 0xF0:
            handleSystemMessage(
                statusByte: statusByte, tick: absoluteTick,
                reader: &reader, trackData: &trackData
            )
        default:
            _ = reader.readByte()
            _ = reader.readByte()
        }
    }

    /// Handles a Note On message (0x90-0x9F).
    static func handleNoteOn(
        channel: UInt8,
        tick: Int,
        reader: inout MIDIDataReader,
        trackData: inout ParsedTrackData
    ) {
        let note = reader.readByte()
        let velocity = reader.readByte()
        if velocity == 0 {
            trackData.noteOffs.append(NoteOffRecord(
                noteNumber: note, absoluteTick: tick, channel: channel
            ))
        } else {
            trackData.noteOns.append(NoteOnRecord(
                noteNumber: note, velocity: velocity,
                absoluteTick: tick, channel: channel
            ))
        }
    }

    /// Handles a Note Off message (0x80-0x8F).
    static func handleNoteOff(
        channel: UInt8,
        tick: Int,
        reader: inout MIDIDataReader,
        trackData: inout ParsedTrackData
    ) {
        let note = reader.readByte()
        _ = reader.readByte()
        trackData.noteOffs.append(NoteOffRecord(
            noteNumber: note, absoluteTick: tick, channel: channel
        ))
    }

    /// Handles system messages (0xF0-0xFF) including meta events.
    static func handleSystemMessage(
        statusByte: UInt8,
        tick: Int,
        reader: inout MIDIDataReader,
        trackData: inout ParsedTrackData
    ) {
        if statusByte == 0xFF {
            handleMetaEvent(
                tick: tick, reader: &reader, trackData: &trackData
            )
        } else if statusByte == 0xF0 || statusByte == 0xF7 {
            let length = reader.readVariableLength()
            reader.skip(length)
        }
    }

    /// Handles a MIDI meta event (0xFF).
    static func handleMetaEvent(
        tick: Int,
        reader: inout MIDIDataReader,
        trackData: inout ParsedTrackData
    ) {
        let metaType = reader.readByte()
        let metaLength = reader.readVariableLength()

        if metaType == 0x51, metaLength == 3 {
            let b0 = Int(reader.readByte())
            let b1 = Int(reader.readByte())
            let b2 = Int(reader.readByte())
            let usPerBeat = (b0 << 16) | (b1 << 8) | b2
            trackData.tempoChanges.append(
                TempoChange(tick: tick, microsecondsPerBeat: usPerBeat)
            )
            let bpm = 60_000_000 / usPerBeat
            logger.debug("Tempo at tick \(tick): \(usPerBeat) µs/beat (\(bpm) BPM)")
        } else {
            reader.skip(metaLength)
        }
    }
}

// MARK: - Note Pairing and Timing

private extension MIDIParser {

    /// Pairs Note On events with their corresponding Note Off events
    /// and converts tick-based timing to absolute seconds.
    static func pairNoteEvents(
        noteOns: [NoteOnRecord],
        noteOffs: [NoteOffRecord],
        tempoChanges: [TempoChange],
        ticksPerQuarterNote: Int
    ) -> [MIDIEvent] {
        let sortedTempo = tempoChanges.sorted { $0.tick < $1.tick }
        let defaultTempo = 500_000
        var events: [MIDIEvent] = []

        for noteOn in noteOns {
            let matchingOff = noteOffs.first { off in
                off.noteNumber == noteOn.noteNumber
                    && off.channel == noteOn.channel
                    && off.absoluteTick > noteOn.absoluteTick
            }

            let offTick = matchingOff?.absoluteTick
                ?? (noteOn.absoluteTick + ticksPerQuarterNote)

            let startSec = tickToSeconds(
                tick: noteOn.absoluteTick,
                tempoChanges: sortedTempo,
                defaultTempo: defaultTempo,
                ticksPerQuarterNote: ticksPerQuarterNote
            )
            let endSec = tickToSeconds(
                tick: offTick,
                tempoChanges: sortedTempo,
                defaultTempo: defaultTempo,
                ticksPerQuarterNote: ticksPerQuarterNote
            )

            events.append(MIDIEvent(
                noteNumber: noteOn.noteNumber,
                velocity: noteOn.velocity,
                timestamp: startSec,
                duration: max(0.01, endSec - startSec)
            ))
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Converts an absolute tick position to seconds,
    /// accounting for tempo changes along the timeline.
    static func tickToSeconds(
        tick: Int,
        tempoChanges: [TempoChange],
        defaultTempo: Int,
        ticksPerQuarterNote: Int
    ) -> TimeInterval {
        var seconds: TimeInterval = 0
        var currentTick = 0
        var currentTempo = defaultTempo
        let divisor = Double(ticksPerQuarterNote) * 1_000_000.0

        for change in tempoChanges {
            if change.tick >= tick { break }
            let delta = change.tick - currentTick
            seconds += Double(delta) * Double(currentTempo) / divisor
            currentTick = change.tick
            currentTempo = change.microsecondsPerBeat
        }

        let remaining = tick - currentTick
        seconds += Double(remaining) * Double(currentTempo) / divisor
        return seconds
    }
}
