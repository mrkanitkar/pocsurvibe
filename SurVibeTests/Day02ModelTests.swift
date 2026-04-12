import Foundation
import Testing

@testable import SurVibe

// MARK: - Song Model Tests

@Suite("Song @Model Tests")
@MainActor
struct SongModelTests {
    @Test("Song default values are correct")
    func defaultValues() {
        let song = Song()
        #expect(song.title == "")
        #expect(song.artist == "")
        #expect(song.language == "hi")
        #expect(song.difficulty == 1)
        #expect(song.category == "folk")
        #expect(song.tempo == 120)
        #expect(song.durationSeconds == 0)
        #expect(song.isFree == false)
        #expect(song.sortOrder == 0)
        #expect(song.midiData == nil)
        #expect(song.sargamNotation == nil)
        #expect(song.westernNotation == nil)
    }

    @Test("Song created with all properties")
    func fullCreation() {
        let song = Song(
            slugId: "test-song-001",
            title: "Test Song",
            artist: "Test Artist",
            language: SongLanguage.hindi.rawValue,
            difficulty: 3,
            category: SongCategory.classical.rawValue,
            ragaName: "Yaman",
            tempo: 96,
            durationSeconds: 180
        )
        #expect(song.slugId == "test-song-001")
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.difficulty == 3)
        #expect(song.ragaName == "Yaman")
        #expect(song.tempo == 96)
        #expect(song.durationSeconds == 180)
    }

    @Test("Song decodes Sargam notes from JSON blob")
    func decodeSargamNotes() throws {
        let notes = [
            SargamNote(note: "Sa", octave: 4, duration: 0.5),
            SargamNote(note: "Re", octave: 4, duration: 0.5),
            SargamNote(note: "Ga", octave: 4, duration: 1.0),
        ]
        let data = try JSONEncoder().encode(notes)
        let song = Song()
        song.sargamNotation = data
        let decoded = song.decodedSargamNotes
        #expect(decoded?.count == 3)
        #expect(decoded?.first?.note == "Sa")
        #expect(decoded?.last?.duration == 1.0)
    }

    @Test("Song decodes Western notes from JSON blob")
    func decodeWesternNotes() throws {
        let notes = [
            WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
            WesternNote(note: "E4", duration: 0.5, midiNumber: 64),
        ]
        let data = try JSONEncoder().encode(notes)
        let song = Song()
        song.westernNotation = data
        let decoded = song.decodedWesternNotes
        #expect(decoded?.count == 2)
        #expect(decoded?.first?.midiNumber == 60)
    }

    @Test("Song returns nil for empty notation data")
    func emptyNotationReturnsNil() {
        let song = Song()
        #expect(song.decodedSargamNotes == nil)
        #expect(song.decodedWesternNotes == nil)
    }

    @Test("SongLanguage enum raw values match ISO 639-1")
    func songLanguageRawValues() {
        #expect(SongLanguage.hindi.rawValue == "hi")
        #expect(SongLanguage.marathi.rawValue == "mr")
        #expect(SongLanguage.english.rawValue == "en")
    }

    @Test("SongCategory enum codable round-trip")
    func songCategoryCodable() throws {
        let original = SongCategory.devotional
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SongCategory.self, from: data)
        #expect(decoded == original)
    }

    @Test("Song computed songLanguage returns typed enum")
    func songLanguageComputed() {
        let song = Song(language: "mr")
        #expect(song.songLanguage == .marathi)
    }

    @Test("Song computed songCategory returns typed enum")
    func songCategoryComputed() {
        let song = Song(category: "classical")
        #expect(song.songCategory == .classical)
    }
}

// MARK: - Lesson Model Tests

@Suite("Lesson @Model Tests")
@MainActor
struct LessonModelTests {
    @Test("Lesson default values are correct")
    func defaultValues() {
        let lesson = Lesson()
        #expect(lesson.title == "")
        #expect(lesson.lessonDescription == "")
        #expect(lesson.difficulty == 1)
        #expect(lesson.orderIndex == 0)
        #expect(lesson.isFree == false)
        #expect(lesson.prerequisiteLessonIds == nil)
        #expect(lesson.associatedSongIds == nil)
        #expect(lesson.stepsData == nil)
    }

    @Test("Lesson decodes prerequisites from JSON blob")
    func decodePrerequisites() throws {
        let prereqs = ["lesson-01-basics", "lesson-02-notation"]
        let data = try JSONEncoder().encode(prereqs)
        let lesson = Lesson()
        lesson.prerequisiteLessonIds = data
        let decoded = lesson.decodedPrerequisites
        #expect(decoded?.count == 2)
        #expect(decoded?.first == "lesson-01-basics")
    }

    @Test("Lesson decodes song IDs from JSON blob")
    func decodeSongIds() throws {
        let songIds = [UUID(), UUID(), UUID()]
        let data = try JSONEncoder().encode(songIds)
        let lesson = Lesson()
        lesson.associatedSongIds = data
        let decoded = lesson.decodedSongIds
        #expect(decoded?.count == 3)
        #expect(decoded?.first == songIds.first)
    }

    @Test("Lesson decodes steps from JSON blob")
    func decodeLessonSteps() throws {
        let steps = [
            LessonStep(stepType: "intro", content: "Welcome to Sa Re Ga"),
            LessonStep(stepType: "exercise", content: "Play Sa three times", durationSeconds: 60),
        ]
        let data = try JSONEncoder().encode(steps)
        let lesson = Lesson()
        lesson.stepsData = data
        let decoded = lesson.decodedSteps
        #expect(decoded?.count == 2)
        #expect(decoded?.first?.stepType == "intro")
        #expect(decoded?.last?.durationSeconds == 60)
    }

    @Test("Lesson returns nil for empty data blobs")
    func emptyDataReturnsNil() {
        let lesson = Lesson()
        #expect(lesson.decodedPrerequisites == nil)
        #expect(lesson.decodedSongIds == nil)
        #expect(lesson.decodedSteps == nil)
    }

    @Test("LessonStep with optional songId")
    func lessonStepWithSongId() throws {
        let songId = UUID()
        let step = LessonStep(stepType: "listen", content: "Listen to the song", songId: songId)
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(LessonStep.self, from: data)
        #expect(decoded.songId == songId)
    }
}

// MARK: - Curriculum Model Tests

@Suite("Curriculum @Model Tests")
@MainActor
struct CurriculumModelTests {
    @Test("Curriculum default values are correct")
    func defaultValues() {
        let curriculum = Curriculum()
        #expect(curriculum.title == "")
        #expect(curriculum.curriculumDescription == "")
        #expect(curriculum.minDifficulty == 1)
        #expect(curriculum.maxDifficulty == 1)
        #expect(curriculum.lessonIds == nil)
    }

    @Test("Curriculum decodes lesson IDs from JSON blob")
    func decodeLessonIds() throws {
        let lessons = ["lesson-01-sa-re-ga", "lesson-02-ma-pa-dha", "lesson-03-ni-sa-high"]
        let data = try JSONEncoder().encode(lessons)
        let curriculum = Curriculum()
        curriculum.lessonIds = data
        let decoded = curriculum.decodedLessonIds
        #expect(decoded?.count == 3)
        #expect(decoded?.first == "lesson-01-sa-re-ga")
    }

    @Test("Curriculum difficulty range computed correctly")
    func difficultyRange() {
        let curriculum = Curriculum(minDifficulty: 2, maxDifficulty: 4)
        #expect(curriculum.difficultyRange == 2...4)
    }

    @Test("Curriculum returns nil for empty lesson IDs")
    func emptyLessonIdsReturnsNil() {
        let curriculum = Curriculum()
        #expect(curriculum.decodedLessonIds == nil)
    }
}

// MARK: - SargamNote / WesternNote Codable Tests

@Suite("Notation Type Tests")
@MainActor
struct NotationTypeTests {
    @Test("SargamNote codable round-trip")
    func sargamNoteCodable() throws {
        let note = SargamNote(note: "Ma", octave: 4, duration: 0.5, modifier: "tivra")
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(SargamNote.self, from: data)
        #expect(decoded == note)
        #expect(decoded.modifier == "tivra")
    }

    @Test("SargamNote without modifier")
    func sargamNoteNoModifier() throws {
        let note = SargamNote(note: "Sa", octave: 4, duration: 1.0)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(SargamNote.self, from: data)
        #expect(decoded.modifier == nil)
    }

    @Test("WesternNote codable round-trip")
    func westernNoteCodable() throws {
        let note = WesternNote(note: "C4", duration: 1.0, midiNumber: 60)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(WesternNote.self, from: data)
        #expect(decoded == note)
        #expect(decoded.midiNumber == 60)
    }
}
