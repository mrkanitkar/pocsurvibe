import Foundation
import SwiftData
import Testing

@testable import SurVibe

// MARK: - SongProgress New Preference Fields Tests
//
// Covers every field added to SongProgress for per-song learner preferences:
// hands, tempo, learner track, wait mode, click track, tanpura, and loop
// region. Tests verify default values (safe for CloudKit max-wins merge)
// and in-memory SwiftData round-trip persistence.

@Suite("SongProgress new pref fields", .serialized)
@MainActor
struct SongProgressFieldsTests {

    // MARK: - Default Values

    @Test("All new pref fields have correct default values on init")
    func defaultValuesAreCorrect() {
        let progress = SongProgress(songId: "yaman", songTitle: "Yaman")

        // Hands
        #expect(progress.preferredHands == "both")
        // Tempo
        #expect(progress.preferredTempoScale == 1.0)
        // Learner track
        #expect(progress.preferredLearnerTrackIndex == 0)
        // Wait mode
        #expect(progress.waitModeEnabled == false)
        // Click track
        #expect(progress.clickTrackEnabled == false)
        #expect(progress.clickTrackLevel == "normal")
        // Tanpura
        #expect(progress.tanpuraEnabled == false)
        #expect(progress.tanpuraRaga.isEmpty)
        // Loop region
        #expect(progress.loopRegionStart == nil)
        #expect(progress.loopRegionEnd == nil)
        // Pre-existing field — regression guard
        #expect(progress.preferredSaHz == nil)
    }

    // MARK: - SwiftData Round-Trip Persistence

    @Test("Non-default pref values survive a SwiftData context save/fetch round-trip")
    func roundTripPersistence() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let progress = SongProgress(songId: "bhairav-rt", songTitle: "Bhairav")
        progress.preferredHands = "right"
        progress.preferredTempoScale = 0.75
        progress.preferredLearnerTrackIndex = 2
        progress.waitModeEnabled = true
        progress.clickTrackEnabled = true
        progress.clickTrackLevel = "soft"
        progress.tanpuraEnabled = true
        progress.tanpuraRaga = "bhairav"
        progress.loopRegionStart = 4
        progress.loopRegionEnd = 16
        context.insert(progress)
        try context.save()

        let descriptor = FetchDescriptor<SongProgress>(
            predicate: #Predicate { $0.songId == "bhairav-rt" }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)

        guard let p = fetched.first else {
            Issue.record("Expected fetched SongProgress, got nil")
            return
        }

        #expect(p.preferredHands == "right")
        #expect(p.preferredTempoScale == 0.75)
        #expect(p.preferredLearnerTrackIndex == 2)
        #expect(p.waitModeEnabled == true)
        #expect(p.clickTrackEnabled == true)
        #expect(p.clickTrackLevel == "soft")
        #expect(p.tanpuraEnabled == true)
        #expect(p.tanpuraRaga == "bhairav")
        #expect(p.loopRegionStart == 4)
        #expect(p.loopRegionEnd == 16)
    }

    // MARK: - Tempo Scale Model Storage

    @Test("preferredTempoScale stores arbitrary values (clamping is VM responsibility)")
    func tempoScaleClampingRangeIsDocumented() {
        let progress = SongProgress(songId: "todi", songTitle: "Todi")

        // Slow practice (50 %)
        progress.preferredTempoScale = 0.5
        #expect(progress.preferredTempoScale == 0.5)

        // Normal (100 %)
        progress.preferredTempoScale = 1.0
        #expect(progress.preferredTempoScale == 1.0)

        // Fast (200 %)
        progress.preferredTempoScale = 2.0
        #expect(progress.preferredTempoScale == 2.0)

        // Clamping is enforced by the ViewModel, not the model itself.
        // The model is a dumb store: whatever the VM writes, it preserves.
        progress.preferredTempoScale = 0.1
        #expect(progress.preferredTempoScale == 0.1)
    }
}
