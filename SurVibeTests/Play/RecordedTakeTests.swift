import Foundation
import SVCore
import SwiftData
import Testing

@testable import SurVibe

/// Round-trip and default-value coverage for the `RecordedTake` SwiftData
/// `@Model`. Verifies that `notesData` blob encoding and the `cachedNotes`
/// transient cache stay in sync with the array passed at construction time.
struct RecordedTakeTests {
    @Test func encodeDecodeNotesBlob() throws {
        let notes = (0..<100).map { i in
            RecordedNote(
                midi: 60,
                velocity: 90,
                onTimeSec: Double(i) * 0.1,
                offTimeSec: Double(i) * 0.1 + 0.08
            )
        }
        let take = RecordedTake(
            title: "Take 1",
            instrumentProgram: 0,
            saPitchMidi: 60,
            notes: notes,
            sustain: []
        )
        #expect(take.noteCount == 100)
        #expect(take.cachedNotes?.count == 100)
        // Re-decode from the stored blob.
        let decoded = try JSONDecoder().decode([RecordedNote].self, from: take.notesData ?? Data())
        #expect(decoded == notes)
    }

    @Test func defaultValues() {
        let take = RecordedTake(
            title: "X",
            instrumentProgram: 0,
            saPitchMidi: 60,
            notes: [],
            sustain: []
        )
        #expect(take.teacherNotes.isEmpty)
        #expect(take.ragaTagId == nil)
        #expect(take.noteCount == 0)
        #expect(take.durationSec == 0)
    }

    @Test func durationFromLastOffTime() {
        let notes = [
            RecordedNote(midi: 60, velocity: 90, onTimeSec: 0.0, offTimeSec: 1.0),
            RecordedNote(midi: 62, velocity: 90, onTimeSec: 1.0, offTimeSec: 2.5),
        ]
        let take = RecordedTake(
            title: "X",
            instrumentProgram: 0,
            saPitchMidi: 60,
            notes: notes,
            sustain: []
        )
        #expect(abs(take.durationSec - 2.5) < 1e-9)
    }
}
