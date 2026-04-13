import Foundation
import Testing

@testable import SurVibe

@Suite("MIDIEventEntry @Model Tests")
@MainActor
struct MIDIEventEntryTests {
    @Test("Default values are correct")
    func defaultValues() {
        let entry = MIDIEventEntry(
            sessionID: UUID(),
            timestamp: 0.0,
            type: "noteOn",
            note: 0,
            velocity: 0,
            channel: 0
        )
        #expect(entry.timestamp.isZero)
        #expect(entry.type == "noteOn")
        #expect(entry.note == .zero)
        #expect(entry.velocity == .zero)
        #expect(entry.channel == .zero)
    }

    @Test("Init sets all fields correctly")
    func initSetsAllFields() {
        let sessionID = UUID()
        let entry = MIDIEventEntry(
            sessionID: sessionID,
            timestamp: 1.5,
            type: "noteOff",
            note: 60,
            velocity: 100,
            channel: 3
        )
        #expect(entry.sessionID == sessionID)
        #expect(entry.timestamp == 1.5)
        #expect(entry.type == "noteOff")
        #expect(entry.note == 60)
        #expect(entry.velocity == 100)
        #expect(entry.channel == 3)
    }

    @Test("Entries with same sessionID share session context")
    func sessionGrouping() {
        let sessionID = UUID()
        let entry1 = MIDIEventEntry(
            sessionID: sessionID,
            timestamp: 0.0,
            type: "noteOn",
            note: 60,
            velocity: 80,
            channel: 0
        )
        let entry2 = MIDIEventEntry(
            sessionID: sessionID,
            timestamp: 0.5,
            type: "noteOff",
            note: 60,
            velocity: 0,
            channel: 0
        )
        #expect(entry1.sessionID == entry2.sessionID)
        #expect(entry1.timestamp < entry2.timestamp)
    }

    @Test("Supports control change event type")
    func controlChangeType() {
        let entry = MIDIEventEntry(
            sessionID: UUID(),
            timestamp: 2.0,
            type: "cc",
            note: 64,
            velocity: 127,
            channel: 0
        )
        #expect(entry.type == "cc")
    }

    @Test("Accepts full MIDI note range")
    func fullMIDIRange() {
        let entry = MIDIEventEntry(
            sessionID: UUID(),
            timestamp: 0.0,
            type: "noteOn",
            note: 127,
            velocity: 127,
            channel: 15
        )
        #expect(entry.note == 127)
        #expect(entry.velocity == 127)
        #expect(entry.channel == 15)
    }
}
