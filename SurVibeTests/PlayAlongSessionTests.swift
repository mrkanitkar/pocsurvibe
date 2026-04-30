import Foundation
import SwiftData
import Testing

@testable import SurVibe

/// Tests for the `PlayAlongSession` SwiftData model.
///
/// Validates default values, split scoring fields, persistence round-trip,
/// and optional field handling. Uses the shared test container to avoid
/// EXC_BREAKPOINT from repeated container creation.
@Suite("PlayAlongSession Model Tests", .serialized)
@MainActor
struct PlayAlongSessionTests {

    // MARK: - Default Values

    @Test("Default scoring fields are zero")
    func defaultScoringFieldsAreZero() {
        let songID = UUID()
        let now = Date()
        let session = PlayAlongSession(songID: songID, startedAt: now)

        #expect(session.notesAttempted == 0)
        #expect(session.notesCorrect == 0)
        #expect(session.notesMissed == 0)
        #expect(session.notesExtra == 0)
        #expect(session.timingAccuracyPercent == 0)
        #expect(session.notesCorrectPercent == 0)
    }

    @Test("Optional fields default to nil")
    func optionalFieldsDefaultToNil() {
        let session = PlayAlongSession(songID: UUID(), startedAt: Date())

        #expect(session.endedAt == nil)
        #expect(session.compositeScore == nil)
        #expect(session.tempoScale == nil)
        #expect(session.practiceMode == nil)
    }

    @Test("ID is a unique UUID")
    func idIsUniqueUUID() {
        let a = PlayAlongSession(songID: UUID(), startedAt: Date())
        let b = PlayAlongSession(songID: UUID(), startedAt: Date())
        #expect(a.id != b.id)
    }

    // MARK: - Init with Values

    @Test("Init populates split scoring fields")
    func initPopulatesSplitScoringFields() {
        let session = PlayAlongSession(
            songID: UUID(),
            startedAt: Date(),
            notesAttempted: 50,
            notesCorrect: 40,
            notesMissed: 8,
            notesExtra: 3,
            timingAccuracyPercent: 0.82,
            notesCorrectPercent: 0.80
        )

        #expect(session.notesAttempted == 50)
        #expect(session.notesCorrect == 40)
        #expect(session.notesMissed == 8)
        #expect(session.notesExtra == 3)
        #expect(session.timingAccuracyPercent == 0.82)
        #expect(session.notesCorrectPercent == 0.80)
    }

    // MARK: - Persistence

    @Test("SwiftData round-trip preserves all fields")
    func swiftDataRoundTripPreservesAllFields() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let songID = UUID()
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = Date(timeIntervalSince1970: 1_700_000_300)

        let session = PlayAlongSession(
            songID: songID,
            startedAt: startDate,
            notesAttempted: 100,
            notesCorrect: 85,
            notesMissed: 10,
            notesExtra: 5,
            timingAccuracyPercent: 0.78,
            notesCorrectPercent: 0.85
        )
        session.endedAt = endDate
        session.compositeScore = 0.81
        session.tempoScale = 0.75
        session.practiceMode = "rightHand"

        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<PlayAlongSession>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)

        let result = try #require(fetched.first)
        #expect(result.songID == songID)
        #expect(result.startedAt == startDate)
        #expect(result.endedAt == endDate)
        #expect(result.notesAttempted == 100)
        #expect(result.notesCorrect == 85)
        #expect(result.notesMissed == 10)
        #expect(result.notesExtra == 5)
        #expect(result.timingAccuracyPercent == 0.78)
        #expect(result.notesCorrectPercent == 0.85)
        #expect(result.compositeScore == 0.81)
        #expect(result.tempoScale == 0.75)
        #expect(result.practiceMode == "rightHand")
    }

    @Test("Multiple sessions for the same song persist independently")
    func multipleSessionsForSameSong() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let songID = UUID()

        let session1 = PlayAlongSession(
            songID: songID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            notesCorrectPercent: 0.60
        )
        let session2 = PlayAlongSession(
            songID: songID,
            startedAt: Date(timeIntervalSince1970: 1_700_001_000),
            notesCorrectPercent: 0.90
        )

        context.insert(session1)
        context.insert(session2)
        try context.save()

        let descriptor = FetchDescriptor<PlayAlongSession>(
            predicate: #Predicate { $0.songID == songID }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 2)
    }
}
