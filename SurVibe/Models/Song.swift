import Foundation
import os
import SVCore
import SwiftData

nonisolated private let songLogger = Logger.survibe(category: "Song")

// MARK: - Supporting Types

/// Language codes for song content metadata.
///
/// Stored as String rawValue for CloudKit compatibility.
/// Uses ISO 639-1 codes for machine-readable language identification.
/// Named `SongLanguage` to avoid conflict with `SupportedLanguage` in Settings.
public enum SongLanguage: String, Codable, Sendable, CaseIterable {
    /// Hindi (हिन्दी)
    case hindi = "hi"
    /// Marathi (मराठी)
    case marathi = "mr"
    /// English
    case english = "en"
}

/// Song category for discovery and filtering.
///
/// Stored as String rawValue for CloudKit compatibility.
public enum SongCategory: String, Codable, Sendable, CaseIterable {
    case folk
    case devotional
    case film
    case classical
    case nursery
    case popular
}

/// A single note in Sargam (Indian classical) notation.
///
/// Used by `NotationContainerView` renderers (`SargamRenderer`, `StaffNotationRenderer`).
/// These renderers currently receive an empty array as a placeholder until the full
/// VerovioBridge → PartSplitter → NoteEvent pipeline is wired into the notation
/// container. The struct is retained so renderers compile; remove it when the
/// pipeline is live and renderers switch to `[NoteEvent]` directly.
public struct SargamNote: Codable, Equatable, Sendable {
    /// Swara note name: Sa, Re, Ga, Ma, Pa, Dha, Ni.
    public let note: String

    /// Octave number (typically 3–5 for piano range).
    public let octave: Int

    /// Duration in quarter-note beats (0.25 = sixteenth, 1.0 = quarter).
    public let duration: Double

    /// Optional modifier for microtonal variants (komal, tivra).
    public let modifier: String?

    public init(note: String, octave: Int, duration: Double, modifier: String? = nil) {
        self.note = note
        self.octave = octave
        self.duration = duration
        self.modifier = modifier
    }
}

/// A single note in Western notation.
///
/// Retained alongside `SargamNote` for use by `WesternRenderer` and
/// `StaffNotationRenderer` in `NotationContainerView`. Remove when those
/// renderers migrate to `[NoteEvent]` directly.
public struct WesternNote: Codable, Equatable, Sendable {
    /// Note name with octave: C4, D4, E4, ..., B4, C5.
    public let note: String

    /// Duration in quarter-note beats (0.25 = sixteenth, 1.0 = quarter).
    public let duration: Double

    /// MIDI note number for reference (0–127).
    public let midiNumber: Int

    public init(note: String, duration: Double, midiNumber: Int) {
        self.note = note
        self.duration = duration
        self.midiNumber = midiNumber
    }
}

// MARK: - Song @Model

/// Represents a single playable song in the SurVibe library.
///
/// T5' (2026-05-01): the canonical source of musical content is now the
/// SMF in `midiData` plus the original MusicXML in `musicXMLData`. The
/// legacy `sargamNotation` / `westernNotation` JSON blobs were dropped —
/// renderers now derive `[NoteEvent]` directly from `midiData` (or, for
/// MXL imports, from `RenderedMIDI` + the MusicXML extractor in T6a).
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values or are optional.
/// - No `@Attribute(.unique)` — CloudKit does not support unique constraints.
/// - Enums are stored as String rawValue.
/// - Binary data uses `@Attribute(.externalStorage)` and optional `Data?`.
///
/// ## Migration: v12 → v13
/// v13 wipes every `Song` row and re-imports only the bundled MXL audition
/// assets through the new pipeline. Sanctioned by the plan-v2 locked
/// decision "CloudKit dev container wipe" (no users yet).
@Model
final class Song {
    // MARK: - Identifiers

    /// Unique identifier (auto-generated UUID).
    var id: UUID = UUID()

    /// Human-readable slug for testing and debugging.
    /// Example: "song-001-raag-yaman-hindi"
    var slugId: String = ""

    // MARK: - Metadata

    /// Display title in the song's primary language.
    var title: String = ""

    /// Artist or composer name.
    var artist: String = ""

    /// Primary language of the lyrics (stored as String rawValue).
    var language: String = SongLanguage.hindi.rawValue

    /// Difficulty level (1 = beginner, 5 = advanced).
    var difficulty: Int = 1

    /// Song category for discovery (stored as String rawValue).
    var category: String = SongCategory.folk.rawValue

    /// Optional raga classification. Not all songs map to a classical raga.
    var ragaName: String = ""

    // MARK: - Playback

    /// Tempo in beats per minute.
    var tempo: Int = 120

    /// Duration in seconds (for progress tracking and UI).
    var durationSeconds: Int = 0

    /// Raw MIDI data (binary-encoded Standard MIDI File).
    @Attribute(.externalStorage) var midiData: Data?

    /// Original MusicXML payload (compressed `.mxl` bytes when imported as
    /// MXL, or UTF-8 plaintext for `.musicxml`). Kept around so we can
    /// re-render through Verovio without losing key sig / time sig / lyrics
    /// / hand assignment metadata. Populated by Wave 3 import path.
    @Attribute(.externalStorage) var musicXMLData: Data?

    // MARK: - Notation Metadata

    /// Key signature raw value for staff notation (e.g., "C major", "G major", "Bb major").
    /// Defaults to "C major"; populated from MusicXML at import time (Wave 3).
    var keySignatureRaw: String = "C major"

    /// Time signature raw value for staff notation (e.g., "4/4", "3/4").
    /// Defaults to "4/4"; populated from MusicXML at import time (Wave 3).
    var timeSignatureRaw: String = "4/4"

    /// Default Sa frequency in Hz.
    ///
    /// Defaults to C4 = 261.6256 Hz. Populated from the MusicXML key
    /// signature at import time (Wave 3). The user can still override per
    /// song via `SongProgress.preferredSaHz`.
    var defaultSaFrequencyHz: Double = 261.6255653005986

    // MARK: - Play-Along Preferences

    /// Index of the MIDI track designated as the learner's part.
    ///
    /// `nil` means the app auto-picks the melody track at load time.
    /// Persisted per song so the user's choice survives across sessions.
    ///
    /// Back-compat single-track field. For multi-track learners
    /// (e.g., piano RH + LH on separate MTrk chunks) read from
    /// `learnerTrackIndices` instead — this field carries `learnerTrackIndices.first`.
    var learnerTrackIndex: Int?

    /// Full set of MIDI track indices designated as the learner's part(s).
    ///
    /// `nil` means the app auto-picks the learner track(s) at load time.
    /// Persisted per song so the user's choice survives across sessions.
    /// Stored as a SwiftData Transformable blob (CloudKit-compatible).
    var learnerTrackIndices: [Int]?

    /// Human-readable summary of the accompaniment instruments.
    ///
    /// Display-only string built at import time, e.g. "Harmonium · Tabla · Strings".
    /// `nil` when the song has no accompaniment metadata.
    var accompanimentInstrumentSummary: String?

    // MARK: - Business Logic

    /// Whether this song is available to free-tier users.
    var isFree: Bool = false

    /// Whether the user has marked this song as a favorite.
    var isFavorite: Bool = false

    /// Source of the song — "admin"/"bundled" for built-in content,
    /// "user" for user-imported songs.
    var source: String = "admin"

    /// Display order in the song library (ascending).
    var sortOrder: Int = 0

    // MARK: - Timestamps

    /// When this song was first added to the library.
    var createdAt: Date = Date()

    /// Last modification timestamp (updated on any content change).
    var updatedAt: Date = Date()

    // MARK: - Computed Properties

    /// Returns the song's language as a typed enum.
    var songLanguage: SongLanguage? {
        SongLanguage(rawValue: language)
    }

    /// Returns the song's category as a typed enum.
    var songCategory: SongCategory? {
        SongCategory(rawValue: category)
    }

    // MARK: - Initialization

    init(
        slugId: String = "",
        title: String = "",
        artist: String = "",
        language: String = SongLanguage.hindi.rawValue,
        difficulty: Int = 1,
        category: String = SongCategory.folk.rawValue,
        ragaName: String = "",
        tempo: Int = 120,
        durationSeconds: Int = 0
    ) {
        self.id = UUID()
        self.slugId = slugId
        self.title = title
        self.artist = artist
        self.language = language
        self.difficulty = difficulty
        self.category = category
        self.ragaName = ragaName
        self.tempo = tempo
        self.durationSeconds = durationSeconds
        self.isFree = false
        self.sortOrder = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
