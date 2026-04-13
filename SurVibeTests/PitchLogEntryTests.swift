import Foundation
import Testing

@testable import SurVibe

@Suite("PitchLogEntry @Model Tests")
@MainActor
struct PitchLogEntryTests {
    @Test("Default values are correct")
    func defaultValues() {
        let entry = PitchLogEntry(
            sessionID: UUID(),
            timestamp: 0.0,
            frequency: 0.0,
            confidence: 0.0,
            note: ""
        )
        #expect(entry.timestamp.isZero)
        #expect(entry.frequency.isZero)
        #expect(entry.confidence.isZero)
        #expect(entry.note.isEmpty)
    }

    @Test("Init sets all fields correctly")
    func initSetsAllFields() {
        let sessionID = UUID()
        let entry = PitchLogEntry(
            sessionID: sessionID,
            timestamp: 2.5,
            frequency: 261.63,
            confidence: 0.95,
            note: "Sa"
        )
        #expect(entry.sessionID == sessionID)
        #expect(entry.timestamp == 2.5)
        #expect(entry.frequency == 261.63)
        #expect(entry.confidence == 0.95)
        #expect(entry.note == "Sa")
    }

    @Test("Entries with same sessionID share session context")
    func sessionGrouping() {
        let sessionID = UUID()
        let entry1 = PitchLogEntry(
            sessionID: sessionID,
            timestamp: 0.0,
            frequency: 261.63,
            confidence: 0.9,
            note: "Sa"
        )
        let entry2 = PitchLogEntry(
            sessionID: sessionID,
            timestamp: 0.5,
            frequency: 293.66,
            confidence: 0.85,
            note: "Re"
        )
        #expect(entry1.sessionID == entry2.sessionID)
        #expect(entry1.timestamp < entry2.timestamp)
    }

    @Test("Handles komal and tivra note names")
    func komalTivraNames() {
        let entry = PitchLogEntry(
            sessionID: UUID(),
            timestamp: 1.0,
            frequency: 277.18,
            confidence: 0.8,
            note: "Komal Re"
        )
        #expect(entry.note == "Komal Re")
    }

    @Test("Handles low confidence detections")
    func lowConfidence() {
        let entry = PitchLogEntry(
            sessionID: UUID(),
            timestamp: 1.0,
            frequency: 100.0,
            confidence: 0.1,
            note: "Ga"
        )
        #expect(entry.confidence < 0.3)
    }
}
