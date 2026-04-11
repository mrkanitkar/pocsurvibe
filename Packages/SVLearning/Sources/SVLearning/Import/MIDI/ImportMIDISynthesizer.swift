import Foundation

/// Generates standard MIDI Type 0 file data from a parsed notation.
///
/// Produces a single-track MIDI file (Type 0) containing note-on and note-off
/// events timed to match the notation's beat durations and tempo.
/// The MIDI data is suitable for storage in `Song.midiData` and playback
/// via `AVAudioUnitSampler`.
///
/// Uses only Foundation — no AudioKit or AVAudioEngine dependency.
/// Pure data transformation: `ParsedNotation` → MIDI bytes.
public struct ImportMIDISynthesizer: ImportMIDISynthesisProtocol {

    /// MIDI channel for all notes (0 = channel 1).
    private static let midiChannel: UInt8 = 0

    /// Default note velocity.
    private static let defaultVelocity: UInt8 = 80

    /// Middle C MIDI note number (C4 = 60).
    private static let middleCMidi: Int = 60

    public init() {}

    // MARK: - ImportMIDISynthesisProtocol

    /// Generates MIDI Type 0 file data from a parsed notation.
    ///
    /// - Parameters:
    ///   - notation: Normalised parsed notation (all notes have octave and duration).
    ///   - tempo: Tempo in BPM for timing MIDI events.
    /// - Returns: Raw MIDI file bytes, or `nil` if notation has no notes.
    /// - Throws: `ImportError.midiSynthesisFailed` if data generation fails.
    public func synthesise(from notation: ParsedNotation, tempo: Int) async throws -> Data? {
        guard !notation.notes.isEmpty else { return nil }

        let effectiveTempo = max(20, min(300, tempo))
        let ticksPerBeat: UInt16 = 480

        // Collect MIDI events
        var events: [MIDIEvent] = []
        var currentTick: UInt32 = 0

        for note in notation.notes {
            let midiNote = midiNoteNumber(for: note)
            guard midiNote >= 0, midiNote <= 127 else { continue }

            let durationBeats = note.durationBeats ?? 1.0
            let durationTicks = UInt32(durationBeats * Double(ticksPerBeat))

            events.append(MIDIEvent(
                tick: currentTick, type: .noteOn,
                note: UInt8(midiNote), velocity: Self.defaultVelocity
            ))
            events.append(MIDIEvent(
                tick: currentTick + durationTicks, type: .noteOff,
                note: UInt8(midiNote), velocity: 0
            ))

            currentTick += durationTicks
        }

        guard !events.isEmpty else { return nil }

        // Sort events by tick (note-offs may interleave with note-ons)
        let sorted = events.sorted { $0.tick < $1.tick }

        // Build MIDI track bytes
        let trackBytes = buildTrackBytes(events: sorted, tempo: effectiveTempo)

        // Build complete MIDI file
        return buildMIDIFile(trackBytes: trackBytes, ticksPerBeat: ticksPerBeat)
    }

    // MARK: - MIDI Note Mapping

    /// Maps a parsed note to a MIDI note number (0–127).
    ///
    /// Sargam notes are mapped relative to C4 (MIDI 60) as Sa.
    /// Western notes use standard chromatic mapping.
    private func midiNoteNumber(for note: ParsedNotation.Note) -> Int {
        let octave = note.octave ?? 4
        let semitone: Int

        // Try western note name first (C, D, E, F, G, A, B + accidentals)
        if let westernSemitone = westernSemitone(for: note.name) {
            semitone = westernSemitone
        } else if let sargamSemitone = sargamSemitone(for: note.name, modifier: note.modifier) {
            semitone = sargamSemitone
        } else {
            return -1 // Unrecognised note — will be skipped
        }

        // MIDI note = (octave + 1) * 12 + semitone (C4 = 60, where octave=4)
        return (octave + 1) * 12 + semitone
    }

    /// Returns the semitone offset (0–11) for a western note name string.
    private func westernSemitone(for name: String) -> Int? {
        let map: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1,
            "D": 2, "D#": 3, "Eb": 3,
            "E": 4,
            "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8,
            "A": 9, "A#": 10, "Bb": 10,
            "B": 11,
        ]
        return map[name]
    }

    /// Returns the semitone offset (0–11) for a sargam note name and modifier.
    ///
    /// Maps sargam names to semitones relative to Sa = C (semitone 0).
    private func sargamSemitone(for name: String, modifier: String?) -> Int? {
        switch name {
        case "Sa": return 0
        case "Re": return modifier == "komal" ? 1 : 2
        case "Ga": return modifier == "komal" ? 3 : 4
        case "Ma": return modifier == "tivra" ? 6 : 5
        case "Pa": return 7
        case "Dha": return modifier == "komal" ? 8 : 9
        case "Ni": return modifier == "komal" ? 10 : 11
        default: return nil
        }
    }

    // MARK: - MIDI File Construction

    /// Builds the byte sequence for a MIDI track chunk including a tempo event.
    private func buildTrackBytes(events: [MIDIEvent], tempo: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var previousTick: UInt32 = 0

        // Tempo meta-event (microseconds per beat)
        let microsecondsPerBeat = UInt32(60_000_000 / tempo)
        let tempoBytes = writeDeltaTime(0) + [0xFF, 0x51, 0x03,
            UInt8((microsecondsPerBeat >> 16) & 0xFF),
            UInt8((microsecondsPerBeat >> 8) & 0xFF),
            UInt8(microsecondsPerBeat & 0xFF)]
        bytes.append(contentsOf: tempoBytes)

        for event in events {
            let delta = event.tick - previousTick
            previousTick = event.tick

            bytes.append(contentsOf: writeDeltaTime(delta))

            switch event.type {
            case .noteOn:
                bytes.append(contentsOf: [0x90 | Self.midiChannel, event.note, event.velocity])
            case .noteOff:
                bytes.append(contentsOf: [0x80 | Self.midiChannel, event.note, event.velocity])
            }
        }

        // End of track meta-event
        bytes.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        return bytes
    }

    /// Encodes a delta time value as variable-length MIDI bytes.
    private func writeDeltaTime(_ value: UInt32) -> [UInt8] {
        if value == 0 { return [0x00] }
        var result: [UInt8] = []
        var v = value
        var first = true
        while v > 0 {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if !first { byte |= 0x80 }
            result.insert(byte, at: 0)
            first = false
        }
        return result
    }

    /// Builds a complete Type 0 MIDI file from track bytes.
    private func buildMIDIFile(trackBytes: [UInt8], ticksPerBeat: UInt16) -> Data {
        var file: [UInt8] = []

        // Header chunk: MThd
        file.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // "MThd"
        file.append(contentsOf: [0x00, 0x00, 0x00, 0x06]) // Length = 6
        file.append(contentsOf: [0x00, 0x00])              // Format = 0 (single track)
        file.append(contentsOf: [0x00, 0x01])              // Number of tracks = 1
        file.append(UInt8((ticksPerBeat >> 8) & 0xFF))
        file.append(UInt8(ticksPerBeat & 0xFF))

        // Track chunk: MTrk
        file.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // "MTrk"
        let trackLength = UInt32(trackBytes.count)
        file.append(UInt8((trackLength >> 24) & 0xFF))
        file.append(UInt8((trackLength >> 16) & 0xFF))
        file.append(UInt8((trackLength >> 8) & 0xFF))
        file.append(UInt8(trackLength & 0xFF))
        file.append(contentsOf: trackBytes)

        return Data(file)
    }
}

// MARK: - MIDIEvent

/// A single timed MIDI note event.
private struct MIDIEvent {
    enum EventType { case noteOn, noteOff }
    let tick: UInt32
    let type: EventType
    let note: UInt8
    let velocity: UInt8
}
