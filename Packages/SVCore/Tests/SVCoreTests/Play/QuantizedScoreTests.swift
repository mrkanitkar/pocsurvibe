import Foundation
import Testing
@testable import SVCore

struct QuantizedScoreTests {
    @Test func emptyScoreHasNoMeasures() {
        let s = QuantizedScore(bpm: 80, timeSignature: .fourFour, measures: [])
        #expect(s.measures.isEmpty)
        #expect(s.bpm == 80)
    }

    @Test func quantizedNoteSplitByStaff() {
        // C4 (60) goes treble; B3 (59) goes bass — matches v1 split at MIDI ≥60.
        let trebleNote = QuantizedNote(
            midi: 60, startBeat: 0, duration: .quarter, velocity: 90, staff: .treble, voice: 1
        )
        let bassNote = QuantizedNote(
            midi: 59, startBeat: 0, duration: .quarter, velocity: 90, staff: .bass, voice: 2
        )
        #expect(trebleNote.staff == .treble)
        #expect(bassNote.staff == .bass)
    }

    @Test func timeSignatureBeatsPerMeasure() {
        #expect(TimeSignature.fourFour.beatsPerMeasure == 4)
        #expect(TimeSignature.threeFour.beatsPerMeasure == 3)
        #expect(TimeSignature.sixEight.beatsPerMeasure == 3)   // 6 eighths = 3 quarter-beats
    }
}
