import SwiftData
import Testing

@testable import SurVibe

// MARK: - Signposter SwiftData Integration Tests

@Suite("Signposter SwiftData Integration")
@MainActor
struct SignposterSwiftDataTests {
    /// Create an in-memory ModelContainer for testing.
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

    @Test func songLibraryViewModelLoadsWithSignposter() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let vm = SongLibraryViewModel(modelContext: context)
        await vm.loadSongs()
        #expect(vm.allSongs.isEmpty) // no songs seeded
    }

    @Test func songLibraryViewModelLoadsSeededSongs() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        // Insert a test song
        let song = Song()
        song.title = "Test Raga"
        song.artist = "Test Artist"
        context.insert(song)
        try context.save()

        let vm = SongLibraryViewModel(modelContext: context)
        await vm.loadSongs()
        #expect(vm.allSongs.count == 1)
        #expect(vm.allSongs.first?.title == "Test Raga")
    }
}
