import Foundation
import SVAudio

/// A unified note event for play-along mode, bridging Sargam/Western notation
/// and MIDI data into a single timeline-ready format.
///
/// NoteEvent is the central data model for the play-along pipeline. It converts
/// heterogeneous song data (notation JSON or MIDI binary) into a uniform sequence
/// of timed, identifiable notes that drive both the visual display (falling notes,
/// scrolling sheet) and the scoring/detection engine.
///
/// ## Two Construction Paths
/// - ``fromNotation(sargamNotes:westernNotes:tempo:)`` — converts beat-based
///   notation arrays into absolute-second timestamps (used by 17/19 seed songs).
/// - ``fromMIDI(events:)`` — wraps parsed MIDI events, deriving Swar names from
///   MIDI note numbers (used by 2/19 seed songs with binary MIDI data).
///
/// ## Swar Name Contract
/// The ``swarName`` property always stores the **full** Swar name including
/// modifier prefix (e.g., "Komal Re", "Tivra Ma"), not just the base note.
/// This matches the format returned by `SwarUtility.frequencyToNote()` and
/// `PitchResult.noteName`, ensuring correct comparison in pitch detection.
struct NoteEvent: Identifiable, Equatable, Sendable {
    /// Unique identifier for SwiftUI list diffing.
    let id: UUID

    /// MIDI note number (0–127). Used for keyboard highlighting and SoundFont playback.
    let midiNote: UInt8

    /// Full Swar name including modifier (e.g., "Sa", "Komal Re", "Tivra Ma").
    ///
    /// This is the canonical name used for pitch detection comparison.
    /// Must match the format from `SwarUtility.frequencyToNote()`.
    let swarName: String

    /// Western note name with octave (e.g., "C4", "Db4", "F#4").
    let westernName: String

    /// Octave number (typically 3–5 for piano range).
    let octave: Int

    /// Absolute start time in seconds from the beginning of the song.
    let timestamp: TimeInterval

    /// Duration of the note in seconds.
    let duration: TimeInterval

    /// Key velocity (1–127). Used for SoundFont playback dynamics.
    let velocity: UInt8

    // MARK: - Notation Path Factory

    /// Convert paired Sargam/Western notation arrays into a timeline of NoteEvents.
    ///
    /// This is the primary conversion path, used by 17 of 19 seed songs that store
    /// notation as JSON arrays but lack binary MIDI data.
    ///
    /// Beat-based durations are converted to absolute seconds using the song's tempo:
    /// ```
    /// durationSeconds = durationBeats * (60.0 / tempo)
    /// timestamp[n] = sum of durationSeconds[0..<n]
    /// ```
    ///
    /// The full Swar name is constructed from `SargamNote.note` and `.modifier`,
    /// matching the format returned by pitch detection (e.g., "Komal Re", not "Re").
    ///
    /// - Parameters:
    ///   - sargamNotes: Array of Sargam notation notes from the song.
    ///   - westernNotes: Array of Western notation notes (must be same length).
    ///   - tempo: Song tempo in beats per minute.
    /// - Returns: Array of NoteEvents with cumulative timestamps.
    static func fromNotation(
        sargamNotes: [SargamNote],
        westernNotes: [WesternNote],
        tempo: Int
    ) -> [NoteEvent] {
        guard sargamNotes.count == westernNotes.count else {
            return []
        }

        let beatsPerSecond = Double(tempo) / 60.0
        var events: [NoteEvent] = []
        var cumulativeTime: TimeInterval = 0

        for index in sargamNotes.indices {
            let sargam = sargamNotes[index]
            let western = westernNotes[index]

            let fullSwarName = Self.fullSwarName(note: sargam.note, modifier: sargam.modifier)
            let durationSeconds = sargam.duration / beatsPerSecond
            let midiNote = UInt8(clamping: western.midiNumber)

            // Note: MIDI note comes from westernNotation (absolute) which is the source of truth.
            // Sargam notation is relative (e.g. G=Sa for Jana Gana Mana), so deriveMIDINote
            // would produce the wrong absolute MIDI number for non-C-root songs.

            let event = NoteEvent(
                id: UUID(),
                midiNote: midiNote,
                swarName: fullSwarName,
                westernName: western.note,
                octave: sargam.octave,
                timestamp: cumulativeTime,
                duration: durationSeconds,
                velocity: 100
            )
            events.append(event)
            cumulativeTime += durationSeconds
        }

        return events
    }

    // MARK: - MIDI Path Factory

    /// Convert parsed MIDI events into NoteEvents with derived Swar names.
    ///
    /// This is the secondary conversion path, used by 2 of 19 seed songs
    /// that have binary MIDI data. Timestamps and durations come directly
    /// from the parsed MIDI file (already in seconds).
    ///
    /// Swar names are derived from MIDI note numbers via the `Swar` enum's
    /// `midiOffset`, producing full names like "Komal Re" (not "Re").
    ///
    /// - Parameter events: Parsed MIDI events sorted by timestamp.
    /// - Returns: Array of NoteEvents preserving MIDI timing.
    static func fromMIDI(events: [MIDIEvent]) -> [NoteEvent] {
        events.map { midi in
            let info = Self.noteNames(fromMIDI: midi.noteNumber)
            return NoteEvent(
                id: UUID(),
                midiNote: midi.noteNumber,
                swarName: info.swarName,
                westernName: info.westernName,
                octave: info.octave,
                timestamp: midi.timestamp,
                duration: midi.duration,
                velocity: midi.velocity
            )
        }
    }

    // MARK: - Private Helpers

    /// Construct the full Swar name from a base note and optional modifier.
    ///
    /// Matches the naming convention used by `Swar.rawValue` and
    /// `SwarUtility.frequencyToNote()`:
    /// - "Sa", "Re", "Ga", etc. (no modifier)
    /// - "Komal Re", "Komal Ga", etc. (komal modifier)
    /// - "Tivra Ma" (tivra modifier)
    ///
    /// - Parameters:
    ///   - note: Base Swar note name (e.g., "Re", "Ma").
    ///   - modifier: Optional modifier string ("komal" or "tivra").
    /// - Returns: Full Swar name for pitch detection comparison.
    static func fullSwarName(note: String, modifier: String?) -> String {
        guard let modifier, !modifier.isEmpty else {
            return note
        }
        return "\(modifier.capitalized) \(note)"
    }

    /// Result of mapping a MIDI note number to Swar/Western names and octave.
    private struct NoteNameInfo {
        let swarName: String
        let westernName: String
        let octave: Int
    }

    /// Derive Swar name, Western name, and octave from a MIDI note number.
    ///
    /// MIDI 60 = C4 = Sa (octave 4). The semitone offset within the octave
    /// maps to a `Swar` case via `midiOffset`.
    ///
    /// - Parameter midiNote: MIDI note number (0–127).
    /// - Returns: A `NoteNameInfo` with swarName, westernName, and octave.
    private static func noteNames(fromMIDI midiNote: UInt8) -> NoteNameInfo {
        let noteNumber = Int(midiNote)
        let octave = (noteNumber / 12) - 1
        let semitone = noteNumber % 12

        // Map semitone offset to Swar
        let swar = Swar.allCases.first { $0.midiOffset == semitone } ?? .sa
        let swarName = swar.rawValue

        // Map semitone to Western note name
        let westernNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        let westernBase = westernNames[semitone]
        let westernName = "\(westernBase)\(octave)"

        return NoteNameInfo(swarName: swarName, westernName: westernName, octave: octave)
    }
}
