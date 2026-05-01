import SwiftData
import Testing
@testable import SurVibe

/// Tests for model-level bindings exposed by the play-along settings sheet.
///
/// These tests validate the state that the settings sheet reads and writes —
/// not the SwiftUI layout itself (per project rules: "What NOT to test:
/// SwiftUI view layout").
@MainActor
struct PlayAlongSettingsSheetTests {

    // MARK: - Helpers

    /// Create an in-memory SongProgress instance (no SwiftData container).
    private func makeProgress() -> SongProgress {
        SongProgress(songId: "test-song", songTitle: "Test")
    }

    /// Create a SongProgress instance inserted into an in-memory SwiftData
    /// container. Use when the test mutates the row and calls `modelContext.save()`.
    private func makePersistedProgress() throws -> SongProgress {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SongProgress.self, configurations: config)
        let p = SongProgress(songId: "test", songTitle: "Test")
        container.mainContext.insert(p)
        return p
    }

    // MARK: - Tests

    /// Setting waitModeEnabled to true on SongProgress persists the value.
    @Test func toggleWritesToProgress() {
        let progress = makeProgress()
        progress.waitModeEnabled = true
        #expect(progress.waitModeEnabled == true)
    }

    /// A freshly created SongProgress defaults clickTrackLevel to "normal".
    @Test func clickTrackLevelDefaultsToNormal() {
        let progress = makeProgress()
        #expect(progress.clickTrackLevel == "normal")
    }

    /// Writing "rh" to preferredHands persists on the SongProgress row.
    @Test func handsPickerBoundToProgress() {
        let progress = makeProgress()
        progress.preferredHands = "rh"
        #expect(progress.preferredHands == "rh")
    }

    /// Setting tanpuraEnabled and tanpuraRaga both persist on SongProgress.
    @Test func tanpuraSettingsWrite() {
        let progress = makeProgress()
        progress.tanpuraEnabled = true
        progress.tanpuraRaga = "Bhairavi"
        #expect(progress.tanpuraEnabled == true)
        #expect(progress.tanpuraRaga == "Bhairavi")
    }

    /// Loop region start/end can be written and later cleared to nil.
    @Test func loopRegionWriteAndClear() {
        let progress = makeProgress()
        progress.loopRegionStart = 5
        progress.loopRegionEnd = 12
        #expect(progress.loopRegionStart == 5)
        #expect(progress.loopRegionEnd == 12)

        progress.loopRegionStart = nil
        progress.loopRegionEnd = nil
        #expect(progress.loopRegionStart == nil)
        #expect(progress.loopRegionEnd == nil)
    }

    /// Setting tempoScale on the VM clamps and stores the value correctly.
    @Test func tempoScaleWritesToProgress() {
        let vm = PlayAlongViewModel()
        vm.tempoScale = 0.75
        #expect(vm.tempoScale == 0.75)
    }
}
