import Foundation
import SVCore
import SwiftData

/// A saved Play tab performance.
///
/// Lives in the app target because SwiftData `@Model` classes must share the
/// module that owns the CloudKit container (see `.claude/rules/app-target.md`).
/// `notesData` and `sustainData` are JSON-encoded blobs; `.externalStorage`
/// spills them to sidecar files (CloudKit treats those as `CKAsset`s,
/// side-stepping the 1 MB record-field limit). `cachedNotes` and
/// `cachedSustain` are `@Transient` decoded caches populated lazily on access.
@Model
public final class RecordedTake {
    /// Stable identifier for the take. Not marked `.unique` because CloudKit
    /// integration does not support unique constraints; UUIDs are unique by
    /// construction so app-level dedup is sufficient.
    public var id: UUID = UUID()
    /// User-visible title (e.g., "Take 5 · 29 Apr 19:42").
    public var title: String = ""
    /// Wall-clock timestamp of when the take was saved.
    public var createdAt: Date = Date()
    /// General MIDI program number used during recording (0–127).
    public var instrumentProgram: UInt8 = 0
    /// MIDI note number representing Sa at recording time, used to
    /// re-render Sargam labels against the take's stored tonic.
    public var saPitchMidi: UInt8 = 60
    /// Optional reference to a raga catalog entry.
    public var ragaTagId: String?
    /// Free-text notes from the student or teacher. Defaults to empty.
    public var teacherNotes: String = ""
    /// Total duration of the take in seconds, computed at save time.
    public var durationSec: Double = 0
    /// Number of recorded notes captured in `notesData`.
    public var noteCount: Int = 0

    /// JSON-encoded `[RecordedNote]` blob, stored externally on disk.
    @Attribute(.externalStorage) public var notesData: Data?
    /// JSON-encoded `[RecordedSustainEvent]` blob, stored externally on disk.
    @Attribute(.externalStorage) public var sustainData: Data?

    /// Lazily-populated decode cache for `notesData`.
    @Transient public var cachedNotes: [RecordedNote]?
    /// Lazily-populated decode cache for `sustainData`.
    @Transient public var cachedSustain: [RecordedSustainEvent]?

    /// Creates a new take, encoding the supplied notes and sustain events to
    /// external-storage blobs and seeding the transient caches.
    ///
    /// - Parameters:
    ///   - id: Stable identifier; defaults to a fresh `UUID`.
    ///   - title: User-visible title.
    ///   - createdAt: Save timestamp; defaults to `.now`.
    ///   - instrumentProgram: GM program in use during recording.
    ///   - saPitchMidi: Tonic MIDI note at recording time.
    ///   - ragaTagId: Optional raga catalog reference.
    ///   - teacherNotes: Free-text annotation; defaults to empty.
    ///   - notes: Captured note array; encoded into `notesData`.
    ///   - sustain: Captured sustain-pedal events; encoded into `sustainData`.
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        instrumentProgram: UInt8,
        saPitchMidi: UInt8,
        ragaTagId: String? = nil,
        teacherNotes: String = "",
        notes: [RecordedNote],
        sustain: [RecordedSustainEvent]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.instrumentProgram = instrumentProgram
        self.saPitchMidi = saPitchMidi
        self.ragaTagId = ragaTagId
        self.teacherNotes = teacherNotes
        self.noteCount = notes.count
        self.durationSec = notes.map(\.offTimeSec).max() ?? 0
        self.notesData = try? JSONEncoder().encode(notes)
        self.sustainData = try? JSONEncoder().encode(sustain)
        self.cachedNotes = notes
        self.cachedSustain = sustain
    }

    /// Decodes `notesData` lazily, returning the cached array if present.
    ///
    /// On decode failure (corrupted blob, schema mismatch) returns an empty
    /// array — callers are expected to surface the error as a "Couldn't load"
    /// row in the takes list rather than crashing.
    ///
    /// - Returns: Decoded notes, or an empty array if no blob is present.
    public func loadNotes() -> [RecordedNote] {
        if let cached = cachedNotes { return cached }
        guard let data = notesData,
              let decoded = try? JSONDecoder().decode([RecordedNote].self, from: data)
        else { return [] }
        cachedNotes = decoded
        return decoded
    }

    /// Decodes `sustainData` lazily, returning the cached array if present.
    ///
    /// - Returns: Decoded sustain events, or an empty array if no blob is present.
    public func loadSustain() -> [RecordedSustainEvent] {
        if let cached = cachedSustain { return cached }
        guard let data = sustainData,
              let decoded = try? JSONDecoder().decode([RecordedSustainEvent].self, from: data)
        else { return [] }
        cachedSustain = decoded
        return decoded
    }
}
