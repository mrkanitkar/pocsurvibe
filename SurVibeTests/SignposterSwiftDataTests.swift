import SwiftData
import Testing

@testable import SurVibe

// MARK: - Signposter SwiftData Integration Tests

/// Serialized + shared container — see `SwiftDataTestContainer.swift`.
@Suite("Signposter SwiftData Integration", .serialized)
@MainActor
struct SignposterSwiftDataTests {
    @Test func songLibraryViewModelLoadsWithSignposter() async throws {
        let context = try SwiftDataTestContainer.freshContext()
        let vm = SongLibraryViewModel(modelContext: context)
        await vm.loadSongs()
        #expect(vm.allSongs.isEmpty) // no songs seeded
    }

    @Test func songLibraryViewModelLoadsSeededSongs() async throws {
        let context = try SwiftDataTestContainer.freshContext()
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
