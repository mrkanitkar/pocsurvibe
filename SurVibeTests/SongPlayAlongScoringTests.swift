// SurVibeTests/SongPlayAlongScoringTests.swift
import Foundation
import Testing
@testable import SurVibe

@MainActor
struct SongPlayAlongScoringTests {

    @Test
    func defaultsAreZero() {
        let s = SongPlayAlongScoring(totalNotes: 10)
        #expect(s.notesHit == 0)
        #expect(s.notesMissed == 0)
        #expect(s.accuracyPercent == 0)
        #expect(s.totalNotes == 10)
    }

    @Test
    func recordHitIncrementsAndComputesAccuracy() {
        let s = SongPlayAlongScoring(totalNotes: 4)
        s.recordHit()
        s.recordHit()
        #expect(s.notesHit == 2)
        #expect(s.accuracyPercent == 50)
    }

    @Test
    func recordMissIncrementsMissesOnly() {
        let s = SongPlayAlongScoring(totalNotes: 4)
        s.recordMiss()
        #expect(s.notesHit == 0)
        #expect(s.notesMissed == 1)
        #expect(s.accuracyPercent == 0)
    }

    @Test
    func resetClearsState() {
        let s = SongPlayAlongScoring(totalNotes: 4)
        s.recordHit()
        s.recordMiss()
        s.reset()
        #expect(s.notesHit == 0)
        #expect(s.notesMissed == 0)
    }

    @Test
    func accuracyHandlesZeroTotal() {
        let s = SongPlayAlongScoring(totalNotes: 0)
        #expect(s.accuracyPercent == 0)
    }
}
