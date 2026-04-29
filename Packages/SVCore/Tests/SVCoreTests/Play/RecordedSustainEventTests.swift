import Foundation
import Testing
@testable import SVCore

struct RecordedSustainEventTests {
    @Test func codableRoundTrip() throws {
        let ev = RecordedSustainEvent(timeSec: 1.25, down: true, channel: 0)
        let data = try JSONEncoder().encode(ev)
        let decoded = try JSONDecoder().decode(RecordedSustainEvent.self, from: data)
        #expect(decoded == ev)
    }

    @Test func downAndUpDistinct() {
        let down = RecordedSustainEvent(timeSec: 1.0, down: true, channel: 0)
        let up = RecordedSustainEvent(timeSec: 1.0, down: false, channel: 0)
        #expect(down != up)
    }
}
