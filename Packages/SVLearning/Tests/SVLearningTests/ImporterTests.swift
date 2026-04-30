import Foundation
import Testing

@testable import SVLearning

// MARK: - SongImportDTO Tests

@Suite("SongImportDTO Tests")
struct SongImportDTOTests {
    @Test("Valid DTO passes validation")
    func validDTOPassesValidation() throws {
        let dto = makeSongDTO()
        try dto.validate()
    }

    @Test("Empty slugId fails validation")
    func emptySlugIdFails() {
        let dto = makeSongDTO(slugId: "")
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Empty title fails validation")
    func emptyTitleFails() {
        let dto = makeSongDTO(title: "")
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Title over 100 characters fails validation")
    func longTitleFails() {
        let dto = makeSongDTO(title: String(repeating: "A", count: 101))
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Invalid language fails validation")
    func invalidLanguageFails() {
        let dto = makeSongDTO(language: "fr")
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Difficulty below 1 fails validation")
    func difficultyTooLowFails() {
        let dto = makeSongDTO(difficulty: 0)
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Difficulty above 5 fails validation")
    func difficultyTooHighFails() {
        let dto = makeSongDTO(difficulty: 6)
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Invalid category fails validation")
    func invalidCategoryFails() {
        let dto = makeSongDTO(category: "jazz")
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Tempo below 1 fails validation")
    func tempoTooLowFails() {
        let dto = makeSongDTO(tempo: 0)
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Duration above 600 fails validation")
    func durationTooHighFails() {
        let dto = makeSongDTO(durationSeconds: 601)
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Empty sargam notation fails validation")
    func emptySargamFails() {
        let dto = makeSongDTO(sargamNotation: [])
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("Empty western notation fails validation")
    func emptyWesternFails() {
        let dto = makeSongDTO(westernNotation: [])
        #expect(throws: SongImportError.self) {
            try dto.validate()
        }
    }

    @Test("SongImportDTO codable round-trip")
    func codableRoundTrip() throws {
        let dto = makeSongDTO()
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(SongImportDTO.self, from: data)
        #expect(decoded == dto)
    }

    @Test("SongImportDTO is Sendable")
    func isSendable() {
        func requireSendable<T: Sendable>(_: T) {}
        requireSendable(makeSongDTO())
    }
}

// MARK: - LessonImportDTO Tests

@Suite("LessonImportDTO Tests")
struct LessonImportDTOTests {
    @Test("Valid DTO passes validation")
    func validDTOPassesValidation() throws {
        let dto = makeLessonDTO()
        try dto.validate()
    }

    @Test("Empty lessonId fails validation")
    func emptyLessonIdFails() {
        let dto = makeLessonDTO(lessonId: "")
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("Empty title fails validation")
    func emptyTitleFails() {
        let dto = makeLessonDTO(title: "")
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("Title over 200 characters fails validation")
    func longTitleFails() {
        let dto = makeLessonDTO(title: String(repeating: "A", count: 201))
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("Empty description fails validation")
    func emptyDescriptionFails() {
        let dto = makeLessonDTO(lessonDescription: "")
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("Description over 1000 characters fails validation")
    func longDescriptionFails() {
        let dto = makeLessonDTO(lessonDescription: String(repeating: "A", count: 1001))
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("Difficulty below 1 fails validation")
    func difficultyTooLowFails() {
        let dto = makeLessonDTO(difficulty: 0)
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("Empty steps fails validation")
    func emptyStepsFails() {
        let dto = makeLessonDTO(steps: [])
        #expect(throws: LessonImportError.self) {
            try dto.validate()
        }
    }

    @Test("LessonImportDTO codable round-trip")
    func codableRoundTrip() throws {
        let dto = makeLessonDTO()
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(LessonImportDTO.self, from: data)
        #expect(decoded == dto)
    }

    @Test("LessonImportDTO is Sendable")
    func isSendable() {
        func requireSendable<T: Sendable>(_: T) {}
        requireSendable(makeLessonDTO())
    }
}

// MARK: - SongImporter Tests

@Suite("SongImporter Tests")
struct SongImporterTests {
    @Test("importSong decodes valid JSON data")
    func importSingleSong() throws {
        let dto = makeSongDTO()
        let data = try JSONEncoder().encode(dto)
        let result = try SongImporter.importSong(from: data)
        #expect(result.slugId == dto.slugId)
        #expect(result.title == dto.title)
    }

    @Test("importSong throws on invalid JSON")
    func importInvalidJSON() {
        let data = Data("not json".utf8)
        #expect(throws: SongImportError.self) {
            try SongImporter.importSong(from: data)
        }
    }

    @Test("importSong throws on invalid DTO values")
    func importInvalidDTO() throws {
        let dto = makeSongDTO(difficulty: 99)
        let data = try JSONEncoder().encode(dto)
        #expect(throws: SongImportError.self) {
            try SongImporter.importSong(from: data)
        }
    }

    @Test("importSongs decodes valid JSON array")
    func importMultipleSongs() throws {
        let dtos = [makeSongDTO(slugId: "song-1"), makeSongDTO(slugId: "song-2")]
        let data = try JSONEncoder().encode(dtos)
        let results = SongImporter.importSongs(from: data)
        #expect(results.count == 2)
    }

    @Test("importSongs skips invalid entries")
    func importSongsSkipsInvalid() throws {
        let valid = makeSongDTO(slugId: "song-valid")
        let invalid = makeSongDTO(slugId: "")
        let dtos = [valid, invalid]
        let data = try JSONEncoder().encode(dtos)
        let results = SongImporter.importSongs(from: data)
        #expect(results.count == 1)
        #expect(results.first?.slugId == "song-valid")
    }

    @Test("importSongs returns empty for invalid JSON")
    func importSongsInvalidJSON() {
        let data = Data("not json".utf8)
        let results = SongImporter.importSongs(from: data)
        #expect(results.isEmpty)
    }
}

// MARK: - LessonImporter Tests

@Suite("LessonImporter Tests")
struct LessonImporterTests {
    @Test("importLesson decodes valid JSON data")
    func importSingleLesson() throws {
        let dto = makeLessonDTO()
        let data = try JSONEncoder().encode(dto)
        let result = try LessonImporter.importLesson(from: data)
        #expect(result.lessonId == dto.lessonId)
        #expect(result.title == dto.title)
    }

    @Test("importLesson throws on invalid JSON")
    func importInvalidJSON() {
        let data = Data("not json".utf8)
        #expect(throws: LessonImportError.self) {
            try LessonImporter.importLesson(from: data)
        }
    }

    @Test("importLessons decodes valid JSON array")
    func importMultipleLessons() throws {
        let dtos = [
            makeLessonDTO(lessonId: "lesson-1"),
            makeLessonDTO(lessonId: "lesson-2"),
        ]
        let data = try JSONEncoder().encode(dtos)
        let results = LessonImporter.importLessons(from: data)
        #expect(results.count == 2)
    }

    @Test("importLessons skips invalid entries")
    func importLessonsSkipsInvalid() throws {
        let valid = makeLessonDTO(lessonId: "lesson-valid")
        let invalid = makeLessonDTO(lessonId: "")
        let dtos = [valid, invalid]
        let data = try JSONEncoder().encode(dtos)
        let results = LessonImporter.importLessons(from: data)
        #expect(results.count == 1)
        #expect(results.first?.lessonId == "lesson-valid")
    }
}

// MARK: - LessonStepDTO Tests

@Suite("LessonStepDTO Tests")
struct LessonStepDTOTests {
    @Test("LessonStepDTO codable round-trip")
    func codableRoundTrip() throws {
        let step = LessonStepDTO(
            stepType: "exercise",
            content: "Play Sa three times",
            songId: "twinkle-hindi-v1",
            durationSeconds: 60
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(LessonStepDTO.self, from: data)
        #expect(decoded == step)
    }

    @Test("LessonStepDTO with nil optionals")
    func nilOptionals() throws {
        let step = LessonStepDTO(stepType: "intro", content: "Welcome")
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(LessonStepDTO.self, from: data)
        #expect(decoded.songId == nil)
        #expect(decoded.durationSeconds == nil)
    }
}

// MARK: - Test Factories

private func makeSongDTO(
    slugId: String = "test-song-v1",
    title: String = "Test Song",
    artist: String = "Test Artist",
    language: String = "hi",
    difficulty: Int = 1,
    category: String = "folk",
    tempo: Int = 80,
    durationSeconds: Int = 60,
    sargamNotation: [SargamNoteDTO]? = nil,
    westernNotation: [WesternNoteDTO]? = nil
) -> SongImportDTO {
    SongImportDTO(
        slugId: slugId,
        title: title,
        artist: artist,
        language: language,
        difficulty: difficulty,
        category: category,
        tempo: tempo,
        durationSeconds: durationSeconds,
        sortOrder: 0,
        midiData: "",
        sargamNotation: sargamNotation ?? [
            SargamNoteDTO(note: "Sa", octave: 4, duration: 1.0)
        ],
        westernNotation: westernNotation ?? [
            WesternNoteDTO(note: "C4", duration: 1.0, midiNumber: 60)
        ],
        ragaName: nil,
        isFree: true,
        keySignature: nil,
        timeSignature: nil
    )
}

private func makeLessonDTO(
    lessonId: String = "test-lesson-v1",
    title: String = "Test Lesson",
    lessonDescription: String = "Test lesson description",
    difficulty: Int = 1,
    steps: [LessonStepDTO]? = nil
) -> LessonImportDTO {
    LessonImportDTO(
        lessonId: lessonId,
        title: title,
        lessonDescription: lessonDescription,
        difficulty: difficulty,
        orderIndex: 0,
        steps: steps ?? [
            LessonStepDTO(stepType: "intro", content: "Welcome")
        ],
        prerequisiteLessonIds: [],
        associatedSongIds: [],
        isFree: true
    )
}
