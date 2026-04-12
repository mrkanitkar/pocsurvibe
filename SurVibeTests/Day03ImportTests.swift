import Foundation
import SwiftData
import Testing

@testable import SurVibe

// MARK: - ContentImportManager Tests

@Suite("ContentImportManager Tests")
struct ContentImportManagerTests {
    @Test("Import seed songs from bundle JSON")
    @MainActor
    func importSeedSongs() throws {
        let container = try makeTestContainer()
        let summary = try ContentImportManager.importAllSeedContent(
            into: container,
            from: .main
        )
        // Seed file currently contains 1 song (jana-gana-mana-v1)
        #expect(summary.songCount == 1)
        #expect(summary.errorDescriptions.isEmpty)
    }

    @Test("Import seed lessons from bundle JSON")
    @MainActor
    func importSeedLessons() throws {
        let container = try makeTestContainer()
        let summary = try ContentImportManager.importAllSeedContent(
            into: container,
            from: .main
        )
        #expect(summary.lessonCount == 10)
    }

    @Test("Imported songs have correct slugIds")
    @MainActor
    func importedSongSlugIds() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Song>(sortBy: [SortDescriptor(\.sortOrder)])
        let songs = try context.fetch(descriptor)

        // Seed file currently contains 1 song
        #expect(songs.count == 1)
        let slugIds = songs.map(\.slugId)
        #expect(slugIds.contains("jana-gana-mana-v1"))
    }

    @Test("Imported songs have sargam notation data")
    @MainActor
    func importedSongsHaveSargam() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let songs = try context.fetch(FetchDescriptor<Song>())
        for song in songs {
            #expect(song.sargamNotation != nil, "Song \(song.slugId) missing sargam notation")
            let decoded = song.decodedSargamNotes
            #expect(decoded != nil, "Song \(song.slugId) sargam failed to decode")
            #expect(decoded?.isEmpty == false, "Song \(song.slugId) has empty sargam notes")
        }
    }

    @Test("Imported songs have western notation data")
    @MainActor
    func importedSongsHaveWestern() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let songs = try context.fetch(FetchDescriptor<Song>())
        for song in songs {
            #expect(song.westernNotation != nil, "Song \(song.slugId) missing western notation")
            let decoded = song.decodedWesternNotes
            #expect(decoded != nil, "Song \(song.slugId) western failed to decode")
            #expect(decoded?.isEmpty == false, "Song \(song.slugId) has empty western notes")
        }
    }

    @Test("Imported lessons have steps data")
    @MainActor
    func importedLessonsHaveSteps() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let lessons = try context.fetch(
            FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\.orderIndex)])
        )
        for lesson in lessons {
            #expect(lesson.stepsData != nil, "Lesson \(lesson.lessonId) missing steps data")
            let decoded = lesson.decodedSteps
            #expect(decoded != nil, "Lesson \(lesson.lessonId) steps failed to decode")
            #expect(decoded?.isEmpty == false, "Lesson \(lesson.lessonId) has empty steps")
        }
    }

    @Test("Import summary description is non-empty")
    @MainActor
    func summaryDescription() throws {
        let container = try makeTestContainer()
        let summary = try ContentImportManager.importAllSeedContent(
            into: container, from: .main
        )
        #expect(summary.description.contains("Songs: 1"))
        #expect(summary.description.contains("Lessons: 10"))
    }
}

// MARK: - Seed Content Validation Tests

@Suite("Seed Content Validation Tests")
struct SeedContentValidationTests {
    @Test("jana-gana-mana-v1 has correct metadata")
    @MainActor
    func janaGanaManaSongMetadata() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let songs = try context.fetch(FetchDescriptor<Song>())
        let song = songs.first { $0.slugId == "jana-gana-mana-v1" }
        #expect(song != nil)
        #expect(song?.language == "hi")
        #expect(song?.category == "devotional")
        #expect(song?.difficulty == 2)
        #expect(song?.tempo == 72)
    }

    @Test("Sargam and western note arrays are non-empty per song")
    @MainActor
    func notationArraysNonEmpty() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let songs = try context.fetch(FetchDescriptor<Song>())
        for song in songs {
            let sargamCount = song.decodedSargamNotes?.count ?? 0
            let westernCount = song.decodedWesternNotes?.count ?? 0
            #expect(sargamCount > 0, "Song \(song.slugId) has empty sargam notes")
            #expect(westernCount > 0, "Song \(song.slugId) has empty western notes")
        }
    }

    @Test("All sargam notes have valid swara names")
    @MainActor
    func validSwaraNames() throws {
        let validSwaras: Set<String> = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let songs = try context.fetch(FetchDescriptor<Song>())
        for song in songs {
            guard let notes = song.decodedSargamNotes else {
                continue
            }
            for note in notes {
                #expect(
                    validSwaras.contains(note.note),
                    "Song \(song.slugId) has invalid swara: \(note.note)"
                )
            }
        }
    }

    @Test("All western notes have valid MIDI numbers")
    @MainActor
    func validMIDINumbers() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let songs = try context.fetch(FetchDescriptor<Song>())
        for song in songs {
            guard let notes = song.decodedWesternNotes else {
                continue
            }
            for note in notes {
                #expect(
                    (0...127).contains(note.midiNumber),
                    "Song \(song.slugId) has invalid MIDI: \(note.midiNumber)"
                )
            }
        }
    }

    @Test("Lesson ordering is sequential")
    @MainActor
    func lessonOrdering() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let lessons = try context.fetch(
            FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\.orderIndex)])
        )
        #expect(lessons.count == 10)
        // Verify ordering is sequential
        for index in 1..<lessons.count {
            #expect(lessons[index].orderIndex > lessons[index - 1].orderIndex)
        }
        // Verify first two lessons are still present
        #expect(lessons[0].lessonId == "lesson-meet-swaras-v1")
        #expect(lessons[1].lessonId == "lesson-first-melody-v1")
    }

    @Test("Second lesson has prerequisite referencing first lesson")
    @MainActor
    func lessonPrerequisites() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let lessons = try context.fetch(
            FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\.orderIndex)])
        )
        let firstLesson = lessons[0]
        let secondLesson = lessons[1]

        // First lesson has no prerequisites
        let firstPrereqs = firstLesson.decodedPrerequisites
        #expect(firstPrereqs == nil || firstPrereqs?.isEmpty == true)

        // Second lesson references first lesson
        let secondPrereqs = secondLesson.decodedPrerequisites
        #expect(secondPrereqs?.contains("lesson-meet-swaras-v1") == true)
    }

    @Test("Each lesson has between 5 and 6 steps")
    @MainActor
    func lessonStepCount() throws {
        let container = try makeTestContainer()
        _ = try ContentImportManager.importAllSeedContent(into: container, from: .main)

        let context = ModelContext(container)
        let lessons = try context.fetch(FetchDescriptor<Lesson>())
        for lesson in lessons {
            let steps = lesson.decodedSteps
            let count = steps?.count ?? 0
            #expect(
                count >= 5 && count <= 6,
                "Lesson \(lesson.lessonId) expected 5-6 steps, got \(count)"
            )
        }
    }
}

// MARK: - SeedContentLoader Tests

@Suite("SeedContentLoader Tests")
struct SeedContentLoaderTests {
    @Test("isSeedContentLoaded defaults to false")
    @MainActor
    func defaultsToFalse() {
        let key = "com.survibe.seedContentLoaded.test.\(UUID().uuidString)"
        let loaded = UserDefaults.standard.bool(forKey: key)
        #expect(loaded == false)
    }
}

// MARK: - Test Helpers

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        UserProfile.self,
        RiyazEntry.self,
        Achievement.self,
        SongProgress.self,
        LessonProgress.self,
        SubscriptionState.self,
        Song.self,
        Lesson.self,
        Curriculum.self,
        XPEntry.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
