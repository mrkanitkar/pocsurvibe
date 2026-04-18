import Testing

@testable import SVAudio

@MainActor
struct PracticeReplayEngineTests {

    // MARK: - Helpers

    /// Create a replay engine with a default performance engine for testing.
    private func makeEngine() -> PracticeReplayEngine {
        PracticeReplayEngine(performanceEngine: PerformanceEngine())
    }

    /// Create a sample set of replay events for testing.
    private func sampleEvents() -> [PracticeReplayEngine.ReplayEvent] {
        [
            PracticeReplayEngine.ReplayEvent(timestamp: 0.0, noteNumber: 60, velocity: 80, channel: 0),
            PracticeReplayEngine.ReplayEvent(timestamp: 0.5, noteNumber: 64, velocity: 90, channel: 0),
            PracticeReplayEngine.ReplayEvent(timestamp: 1.0, noteNumber: 67, velocity: 100, channel: 0),
        ]
    }

    // MARK: - CRC32 Checksum (MIN-16)

    @Test func computeCRC32ProducesDeterministicResult() {
        let events = sampleEvents()
        let first = PracticeReplayEngine.computeCRC32(events: events)
        let second = PracticeReplayEngine.computeCRC32(events: events)
        #expect(first == second)
        #expect(first.count == 8, "CRC32 hex string should be 8 characters")
    }

    @Test func computeCRC32DiffersForDifferentEvents() {
        let events1 = sampleEvents()
        let events2 = [
            PracticeReplayEngine.ReplayEvent(timestamp: 0.0, noteNumber: 61, velocity: 80, channel: 0),
            PracticeReplayEngine.ReplayEvent(timestamp: 0.5, noteNumber: 64, velocity: 90, channel: 0),
        ]
        let crc1 = PracticeReplayEngine.computeCRC32(events: events1)
        let crc2 = PracticeReplayEngine.computeCRC32(events: events2)
        #expect(crc1 != crc2)
    }

    @Test func computeCRC32EmptyEventsReturnsValidHex() {
        let crc = PracticeReplayEngine.computeCRC32(events: [])
        #expect(crc == "00000000", "Empty events should produce zero CRC")
    }

    @Test func verifyChecksumMatchingSetsNoWarning() {
        let engine = makeEngine()
        let events = sampleEvents()
        let checksum = PracticeReplayEngine.computeCRC32(events: events)
        let result = engine.verifyChecksum(checksum, events: events)
        #expect(result == true)
        #expect(engine.replayIntegrityWarning == false)
    }

    @Test func verifyChecksumMismatchSetsWarning() {
        let engine = makeEngine()
        let events = sampleEvents()
        let result = engine.verifyChecksum("deadbeef", events: events)
        #expect(result == false)
        #expect(engine.replayIntegrityWarning == true)
    }

    @Test func startReplayResetsIntegrityWarning() {
        let engine = makeEngine()
        // Trigger a warning first.
        engine.verifyChecksum("badcheck", events: sampleEvents())
        #expect(engine.replayIntegrityWarning == true)

        // Starting replay resets the flag.
        engine.startReplay(events: sampleEvents())
        #expect(engine.replayIntegrityWarning == false)
        engine.stop()
    }

    @Test func startReplayWithChecksumVerifiesIntegrity() {
        let engine = makeEngine()
        let events = sampleEvents()
        let correctChecksum = PracticeReplayEngine.computeCRC32(events: events)
        engine.startReplay(events: events, expectedChecksum: correctChecksum)
        #expect(engine.replayIntegrityWarning == false)
        engine.stop()
    }

    @Test func startReplayWithBadChecksumSetsWarning() {
        let engine = makeEngine()
        let events = sampleEvents()
        engine.startReplay(events: events, expectedChecksum: "00000000")
        #expect(engine.replayIntegrityWarning == true)
        engine.stop()
    }

    // MARK: - Score Divergence (MIN-17)

    @Test func checkScoreDivergenceNoDivergence() {
        let engine = makeEngine()
        engine.originalScores = [
            OriginalScore(noteIndex: 0, compositeAccuracy: 0.95),
            OriginalScore(noteIndex: 1, compositeAccuracy: 0.80),
        ]
        engine.checkScoreDivergence(replayedScore: 0.95, noteIndex: 0)
        engine.checkScoreDivergence(replayedScore: 0.80, noteIndex: 1)
        #expect(engine.scoreDivergenceCount == 0)
    }

    @Test func checkScoreDivergenceWithinTolerance() {
        let engine = makeEngine()
        engine.originalScores = [
            OriginalScore(noteIndex: 0, compositeAccuracy: 0.95),
        ]
        // 0.005 difference is within 0.01 tolerance.
        engine.checkScoreDivergence(replayedScore: 0.955, noteIndex: 0)
        #expect(engine.scoreDivergenceCount == 0)
    }

    @Test func checkScoreDivergenceExceedsTolerance() {
        let engine = makeEngine()
        engine.originalScores = [
            OriginalScore(noteIndex: 0, compositeAccuracy: 0.95),
        ]
        // 0.02 difference exceeds 0.01 tolerance.
        engine.checkScoreDivergence(replayedScore: 0.97, noteIndex: 0)
        #expect(engine.scoreDivergenceCount == 1)
    }

    @Test func checkScoreDivergenceIgnoresOutOfRangeIndex() {
        let engine = makeEngine()
        engine.originalScores = [
            OriginalScore(noteIndex: 0, compositeAccuracy: 0.95),
        ]
        // Note index 5 is beyond originalScores — should be ignored.
        engine.checkScoreDivergence(replayedScore: 0.50, noteIndex: 5)
        #expect(engine.scoreDivergenceCount == 0)
    }

    @Test func startReplayResetsDivergenceCount() {
        let engine = makeEngine()
        engine.originalScores = [
            OriginalScore(noteIndex: 0, compositeAccuracy: 0.95),
        ]
        engine.checkScoreDivergence(replayedScore: 0.50, noteIndex: 0)
        #expect(engine.scoreDivergenceCount == 1)

        // Starting a new replay resets the count.
        engine.startReplay(events: sampleEvents())
        #expect(engine.scoreDivergenceCount == 0)
        engine.stop()
    }

    // MARK: - OriginalScore

    @Test func originalScoreInit() {
        let score = OriginalScore(noteIndex: 3, compositeAccuracy: 0.87)
        #expect(score.noteIndex == 3)
        #expect(score.compositeAccuracy == 0.87)
    }

    // MARK: - Replay State

    @Test func defaultStateProperties() {
        let engine = makeEngine()
        #expect(engine.isReplaying == false)
        #expect(engine.replayIntegrityWarning == false)
        #expect(engine.scoreDivergenceCount == 0)
        #expect(engine.currentPosition == 0)
        #expect(engine.speed == 1.0)
    }

    @Test func stopResetsState() {
        let engine = makeEngine()
        engine.startReplay(events: sampleEvents())
        engine.stop()
        #expect(engine.isReplaying == false)
        #expect(engine.currentPosition == 0)
    }
}
