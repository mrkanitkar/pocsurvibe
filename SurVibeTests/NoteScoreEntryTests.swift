import Foundation
import Testing

@testable import SurVibe

@Suite("NoteScoreEntry @Model Tests")
@MainActor
struct NoteScoreEntryTests {
    @Test("Default values are correct for all fields")
    func defaultValues() {
        let entry = NoteScoreEntry()
        #expect(entry.noteIndex == .zero)
        #expect(entry.pitchAccuracy == .zero)
        #expect(entry.timingAccuracy == .zero)
        #expect(entry.durationAccuracy == .zero)
        #expect(entry.compositeScore == .zero)
        #expect(entry.grade.isEmpty)
        #expect(entry.expectedNote.isEmpty)
        #expect(entry.playedFrequency == .zero)
        #expect(entry.detectedNote.isEmpty)
        #expect(entry.pitchDeviationCents == .zero)
    }

    @Test("Init sets all fields correctly")
    func initSetsAllFields() {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_000)

        let entry = NoteScoreEntry(
            sessionID: sessionID,
            noteIndex: 3,
            pitchAccuracy: 0.95,
            timingAccuracy: 0.80,
            durationAccuracy: 0.70,
            compositeScore: 0.85,
            grade: "perfect",
            expectedNote: "Sa",
            playedFrequency: 261.63,
            detectedNote: "Sa",
            pitchDeviationCents: -5.2,
            timestamp: timestamp
        )

        #expect(entry.sessionID == sessionID)
        #expect(entry.noteIndex == 3)
        #expect(entry.pitchAccuracy == 0.95)
        #expect(entry.timingAccuracy == 0.80)
        #expect(entry.durationAccuracy == 0.70)
        #expect(entry.compositeScore == 0.85)
        #expect(entry.grade == "perfect")
        #expect(entry.expectedNote == "Sa")
        #expect(entry.playedFrequency == 261.63)
        #expect(entry.detectedNote == "Sa")
        #expect(entry.pitchDeviationCents == -5.2)
        #expect(entry.timestamp == timestamp)
    }

    @Test("Grade stores NoteGrade rawValue as String")
    func gradeStoresRawValue() {
        let perfectEntry = NoteScoreEntry(grade: "perfect")
        let goodEntry = NoteScoreEntry(grade: "good")
        let fairEntry = NoteScoreEntry(grade: "fair")
        let missEntry = NoteScoreEntry(grade: "miss")

        #expect(perfectEntry.grade == "perfect")
        #expect(goodEntry.grade == "good")
        #expect(fairEntry.grade == "fair")
        #expect(missEntry.grade == "miss")
    }

    @Test("Multiple entries with same sessionID share identifier")
    func multipleEntriesShareSessionID() {
        let sharedSessionID = UUID()

        let entry1 = NoteScoreEntry(sessionID: sharedSessionID, noteIndex: 0, expectedNote: "Sa")
        let entry2 = NoteScoreEntry(sessionID: sharedSessionID, noteIndex: 1, expectedNote: "Re")
        let entry3 = NoteScoreEntry(sessionID: sharedSessionID, noteIndex: 2, expectedNote: "Ga")

        #expect(entry1.sessionID == sharedSessionID)
        #expect(entry2.sessionID == sharedSessionID)
        #expect(entry3.sessionID == sharedSessionID)
    }

    @Test("Each entry gets unique id")
    func uniqueIDs() {
        let entry1 = NoteScoreEntry()
        let entry2 = NoteScoreEntry()
        #expect(entry1.id != entry2.id)
    }

    @Test("Negative pitch deviation stores correctly")
    func negativePitchDeviation() {
        let entry = NoteScoreEntry(pitchDeviationCents: -25.5)
        #expect(entry.pitchDeviationCents == -25.5)
    }

    @Test("Timestamp defaults to current date")
    func timestampDefaultsToNow() {
        let before = Date()
        let entry = NoteScoreEntry()
        let after = Date()
        #expect(entry.timestamp >= before)
        #expect(entry.timestamp <= after)
    }
}
