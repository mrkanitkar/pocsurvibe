import Foundation
import os
import SwiftData

private let songLogger = Logger(subsystem: "com.survibe", category: "Song")

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
/// Used inside the Song model's `sargamNotation` JSON blob.
/// Encodes note name, octave, and rhythmic duration.
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
/// Used inside the Song model's `westernNotation` JSON blob.
/// Includes MIDI note number for direct playback mapping.
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
/// A Song combines musical notation (both Sargam and Western),
/// MIDI data for playback, and metadata for discovery and analytics.
/// Stored in SwiftData with CloudKit automatic sync.
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values or are optional.
/// - No `@Attribute(.unique)` — CloudKit does not support unique constraints.
/// - Enums are stored as String rawValue.
/// - Binary data uses `@Attribute(.externalStorage)` and optional `Data?`.
/// - Relationships are stored as JSON-encoded ID arrays, not @Relationship.
///
/// ## Conflict Resolution
/// - `sortOrder` and metadata: last-write-wins (server merge).
/// - `updatedAt`: max-wins for consistency.
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

    // MARK: - Notation

    /// Sargam notation as JSON-encoded `[SargamNote]`.
    @Attribute(.externalStorage) var sargamNotation: Data?

    /// Western notation as JSON-encoded `[WesternNote]`.
    @Attribute(.externalStorage) var westernNotation: Data?

    /// Key signature raw value for staff notation (e.g., "C", "G", "Bb").
    /// Empty string defaults to C Major.
    var keySignatureRaw: String = ""

    /// Time signature raw value for staff notation (e.g., "4/4", "3/4").
    /// Empty string defaults to 4/4.
    var timeSignatureRaw: String = ""

    // MARK: - Business Logic

    /// Whether this song is available to free-tier users.
    var isFree: Bool = false

    /// Whether the user has marked this song as a favorite.
    var isFavorite: Bool = false

    /// Source of the song — "admin" for built-in content, "user" for user-imported songs.
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

    /// Decodes Sargam notes from the JSON blob.
    var decodedSargamNotes: [SargamNote]? {
        guard let data = sargamNotation else { return nil }
        do {
            return try JSONDecoder().decode([SargamNote].self, from: data)
        } catch {
            songLogger.debug("Failed to decode sargam notes for song \(self.slugId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Decodes Western notes from the JSON blob.
    var decodedWesternNotes: [WesternNote]? {
        guard let data = westernNotation else { return nil }
        do {
            return try JSONDecoder().decode([WesternNote].self, from: data)
        } catch {
            songLogger.debug("Failed to decode western notes for song \(self.slugId): \(error.localizedDescription)")
            return nil
        }
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
