import Foundation
import Testing
@testable import SVCore

struct QuantizerTests {
    /// Sa-Re-Ga-Ma at 80 BPM, 1/16 grid, 4/4. Each note exactly 1 beat (= 0.75 s @ 80 BPM).
    @Test func saReGaMaQuarters() throws {
        let beat = 60.0 / 80.0  // 0.75 s
        let notes = [
            RecordedNote(midi: 60, velocity: 90, onTimeSec: 0, offTimeSec: beat),
            RecordedNote(midi: 62, velocity: 90, onTimeSec: beat, offTimeSec: 2 * beat),
            RecordedNote(midi: 64, velocity: 90, onTimeSec: 2 * beat, offTimeSec: 3 * beat),
            RecordedNote(midi: 65, velocity: 90, onTimeSec: 3 * beat, offTimeSec: 4 * beat),
        ]
        let result = Quantizer.quantize(
            notes: notes, sustain: [],
            bpm: 80, timeSignature: .fourFour, grid: .sixteenth
        )
        let score = try result.get()
        #expect(score.bpm == 80)
        #expect(score.timeSignature == .fourFour)
        #expect(score.measures.count == 1)
        #expect(score.measures[0].notes.count == 4)
        #expect(score.measures[0].notes.allSatisfy { $0.duration == .quarter })
        #expect(score.measures[0].notes.map(\.startBeat) == [0, 1, 2, 3])
    }

    @Test func staffSplitAtMidi60() throws {
        let beat = 0.75
        let notes = [
            RecordedNote(midi: 59, velocity: 90, onTimeSec: 0, offTimeSec: beat),       // bass
            RecordedNote(midi: 60, velocity: 90, onTimeSec: beat, offTimeSec: 2 * beat),  // treble
        ]
        let result = Quantizer.quantize(
            notes: notes, sustain: [], bpm: 80,
            timeSignature: .fourFour, grid: .sixteenth
        )
        let score = try result.get()
        #expect(score.measures[0].notes[0].staff == .bass)
        #expect(score.measures[0].notes[0].voice == 2)
        #expect(score.measures[0].notes[1].staff == .treble)
        #expect(score.measures[0].notes[1].voice == 1)
    }

    @Test func emptyInputReturnsEmptyScore() throws {
        let result = Quantizer.quantize(
            notes: [], sustain: [], bpm: 80,
            timeSignature: .fourFour, grid: .sixteenth
        )
        let score = try result.get()
        #expect(score.measures.isEmpty)
    }

    @Test func eighthGridSnapsHalfBeatNotes() throws {
        let beat = 0.75
        // Note that should snap to startBeat = 0.5 on 1/8 grid.
        let notes = [
            RecordedNote(midi: 60, velocity: 90, onTimeSec: 0.49 * beat, offTimeSec: 1.0 * beat),
        ]
        let result = Quantizer.quantize(
            notes: notes, sustain: [], bpm: 80,
            timeSignature: .fourFour, grid: .eighth
        )
        let score = try result.get()
        #expect(abs(score.measures[0].notes[0].startBeat - 0.5) < 1e-9)
    }

    @Test func notesSpanMultipleMeasures() throws {
        let beat = 0.75
        var notes: [RecordedNote] = []
        // 8 quarter notes — 2 measures of 4/4.
        for i in 0..<8 {
            notes.append(RecordedNote(
                midi: 60, velocity: 90,
                onTimeSec: Double(i) * beat,
                offTimeSec: Double(i + 1) * beat
            ))
        }
        let result = Quantizer.quantize(
            notes: notes, sustain: [], bpm: 80,
            timeSignature: .fourFour, grid: .sixteenth
        )
        let score = try result.get()
        #expect(score.measures.count == 2)
        #expect(score.measures[0].notes.count == 4)
        #expect(score.measures[1].notes.count == 4)
    }

    @Test func absurdBPMReturnsError() throws {
        let result = Quantizer.quantize(
            notes: [], sustain: [], bpm: 0,
            timeSignature: .fourFour, grid: .sixteenth
        )
        switch result {
        case .success: Issue.record("expected failure")
        case .failure: break
        }
    }
}
