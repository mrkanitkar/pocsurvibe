import Foundation
import Testing
@testable import SVCore

struct RecordedNoteTests {
    @Test func codableRoundTrip() throws {
        let note = RecordedNote(
            midi: 60, velocity: 100, velocity16Bit: 12_800,
            onTimeSec: 0.125, offTimeSec: 0.250, channel: 0
        )
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(RecordedNote.self, from: data)
        #expect(decoded == note)
    }

    @Test func codableRoundTripArray5000() throws {
        let notes = (0..<5000).map { i in
            RecordedNote(
                midi: UInt8(40 + (i % 40)), velocity: 90, velocity16Bit: 0,
                onTimeSec: Double(i) * 0.1, offTimeSec: Double(i) * 0.1 + 0.08, channel: 0
            )
        }
        let data = try JSONEncoder().encode(notes)
        let decoded = try JSONDecoder().decode([RecordedNote].self, from: data)
        #expect(decoded.count == 5000)
        #expect(decoded.first == notes.first)
        #expect(decoded.last == notes.last)
    }

    @Test func equalityAndHash() {
        let id = UUID()
        let a = RecordedNote(id: id, midi: 60, velocity: 100, onTimeSec: 0, offTimeSec: 1)
        let b = RecordedNote(id: id, midi: 60, velocity: 100, onTimeSec: 0, offTimeSec: 1)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
