import Foundation

// MARK: - MusicTime

/// Canonical beat↔seconds conversion utility for audio time math.
///
/// All BPM-based time conversions in SVAudio MUST go through this enum to ensure
/// there is exactly one implementation. Placing this in SVAudio (not SVCore) keeps
/// the dependency direction correct: `Swar` lives in SVAudio, and SVCore must not
/// depend on SVAudio.
///
/// ## Usage
///
/// ```swift
/// let duration = MusicTime.beatsToSeconds(beats: 4.0, bpm: 120.0) // 2.0
/// let beats    = MusicTime.secondsToBeats(seconds: 2.0, bpm: 120.0) // 4.0
/// ```
public enum MusicTime {

    // MARK: - Beat ↔ Seconds

    /// Convert a beat count to seconds at a given BPM.
    ///
    /// Uses the standard formula: seconds = beats × (60 / BPM).
    ///
    /// - Parameters:
    ///   - beats: Duration or position in beats.
    ///   - bpm: Tempo in beats per minute. Must be positive; values ≤ 0 clamp to 1.
    /// - Returns: Equivalent duration in seconds.
    public static func beatsToSeconds(beats: Double, bpm: Double) -> Double {
        let safeBPM = max(1.0, bpm)
        return beats * 60.0 / safeBPM
    }

    /// Convert seconds to a beat count at a given BPM.
    ///
    /// Uses the standard formula: beats = seconds × (BPM / 60).
    ///
    /// - Parameters:
    ///   - seconds: Duration or position in seconds.
    ///   - bpm: Tempo in beats per minute. Must be positive; values ≤ 0 clamp to 1.
    /// - Returns: Equivalent beat count.
    public static func secondsToBeats(seconds: Double, bpm: Double) -> Double {
        let safeBPM = max(1.0, bpm)
        return seconds * safeBPM / 60.0
    }
}

// MARK: - Swar + MIDI

extension Swar {

    /// Sargam name for a MIDI note number (A4 = 440 Hz / MIDI 69 standard tuning).
    ///
    /// Maps the semitone offset within the octave (note % 12) to the canonical
    /// `Swar.rawValue` string (e.g. "Sa", "Komal Re", "Tivra Ma"). Uses the
    /// O(1) `Swar.nameForSemitone` lookup table to avoid linear scans.
    ///
    /// - Parameter midi: MIDI note number (0–127).
    /// - Returns: Full Swar name (e.g., `"Komal Re"`). Falls back to `"Sa"` for
    ///            any unrecognised semitone.
    public static func sargamName(forMIDI midi: UInt8) -> String {
        let semitone = Int(midi) % 12
        return nameForSemitone[semitone] ?? Swar.sa.rawValue
    }

    /// Western note name (e.g., `"C4"`, `"Eb3"`, `"F#5"`) for a MIDI note number.
    ///
    /// Maps MIDI note to octave and semitone, then formats as `<pitch><octave>`
    /// using the standard flat-preferred spelling (Db, Eb, F#, Ab, Bb). Octave
    /// numbering follows the MIDI convention: C4 = MIDI 60.
    ///
    /// - Parameter midi: MIDI note number (0–127).
    /// - Returns: Western note name string such as `"C4"` or `"Bb3"`.
    public static func westernName(forMIDI midi: UInt8) -> String {
        let noteNumber = Int(midi)
        // MIDI octave: C4 = MIDI 60, so octave = (noteNumber / 12) - 1
        let octave = (noteNumber / 12) - 1
        let semitone = noteNumber % 12
        let pitchNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return "\(pitchNames[semitone])\(octave)"
    }
}
