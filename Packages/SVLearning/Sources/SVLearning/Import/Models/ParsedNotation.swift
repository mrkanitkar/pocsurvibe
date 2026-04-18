import Foundation

/// The result of successfully parsing a notation input.
///
/// Contains the structured note sequence along with inferred or declared
/// metadata. This is an intermediate representation — not yet validated or
/// normalised.
public struct ParsedNotation: Sendable {

    /// A single parsed note event.
    public struct Note: Sendable {
        /// Note name as a string (e.g. "Sa", "Re", "C4", "D#3").
        public let name: String
        /// Octave number (1–7). Nil if not yet inferred.
        public var octave: Int?
        /// Duration in beats (1.0 = quarter note). Nil if not yet inferred.
        public var durationBeats: Double?
        /// Optional modifier string ("komal", "tivra", "#", "b").
        public let modifier: String?
        /// Zero-based position index within the sequence.
        public let index: Int
        /// Optional velocity (0–127). Nil means use default (100).
        ///
        /// Populated from notation markup (e.g. `p`, `f`, `mf` dynamic markings)
        /// or MIDI import. When nil, consumers should fall back to velocity 100.
        public var velocity: UInt8?

        /// Creates a parsed note.
        public init(
            name: String, octave: Int? = nil, durationBeats: Double? = nil,
            modifier: String? = nil, index: Int, velocity: UInt8? = nil
        ) {
            self.name = name
            self.octave = octave
            self.durationBeats = durationBeats
            self.modifier = modifier
            self.index = index
            self.velocity = velocity
        }
    }

    /// Detected or declared notation format.
    public let format: NotationInput.Format

    /// Ordered sequence of parsed notes.
    public var notes: [Note]

    /// Inferred or user-supplied tempo in BPM.
    public var tempo: Int

    /// Key signature string (e.g. "C major", "G major"). Empty if not detected.
    public var keySignature: String

    /// Time signature string (e.g. "4/4", "3/4"). Defaults to "4/4".
    public var timeSignature: String

    /// Name of the raga, if detected from notation metadata.
    ///
    /// Populated by the Sargam parser when the notation header contains
    /// a raga declaration (e.g., `raga: Yaman`). Used by `RagaScoringContext`
    /// for context-aware scoring.
    public var ragaName: String?

    /// Creates a parsed notation result.
    public init(
        format: NotationInput.Format,
        notes: [Note],
        tempo: Int = 120,
        keySignature: String = "",
        timeSignature: String = "4/4",
        ragaName: String? = nil
    ) {
        self.format = format
        self.notes = notes
        self.tempo = tempo
        self.keySignature = keySignature
        self.timeSignature = timeSignature
        self.ragaName = ragaName
    }
}
