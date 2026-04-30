// SurVibeTests/PlayAlong/SectionLoopControllerTests.swift
import Testing

@testable import SurVibe

/// Unit tests for `SectionLoopController` (Wave 3 Task C3).
///
/// `SectionLoopController` is a pure value-type calculator that converts
/// a `LoopRegion` (1-indexed measure range) into beat-space boundaries
/// and decides when playback should wrap. No actor isolation required.
@Suite("SectionLoopController")
struct SectionLoopControllerTests {

    @Test func startBeatComputesFromMeasure1Indexed() {
        let lc = SectionLoopController(
            region: LoopRegion(startMeasure: 5, endMeasure: 8),
            beatsPerMeasure: 4
        )
        // Measure 5 in 4/4 starts at beat (5-1)*4 = 16.
        #expect(lc.startBeat == 16)
        // endMeasure is inclusive, so endBeat = 8*4 = 32.
        #expect(lc.endBeat == 32)
    }

    @Test func shouldWrapTrueAtOrPastEndBeat() {
        let lc = SectionLoopController(
            region: LoopRegion(startMeasure: 5, endMeasure: 8),
            beatsPerMeasure: 4
        )
        #expect(lc.shouldWrap(currentBeat: 32))
        #expect(lc.shouldWrap(currentBeat: 32.5))
        #expect(lc.shouldWrap(currentBeat: 100))
    }

    @Test func shouldWrapFalseInsideRegion() {
        let lc = SectionLoopController(
            region: LoopRegion(startMeasure: 5, endMeasure: 8),
            beatsPerMeasure: 4
        )
        #expect(lc.shouldWrap(currentBeat: 0) == false)
        #expect(lc.shouldWrap(currentBeat: 16) == false)
        #expect(lc.shouldWrap(currentBeat: 31.999) == false)
    }

    @Test func startBeatHonorsBeatsPerMeasure() {
        // 3/4 time, measures 3..4 → startBeat = (3-1)*3 = 6, endBeat = 4*3 = 12.
        let lc = SectionLoopController(
            region: LoopRegion(startMeasure: 3, endMeasure: 4),
            beatsPerMeasure: 3
        )
        #expect(lc.startBeat == 6)
        #expect(lc.endBeat == 12)
    }

    @Test func loopRegionEquatable() {
        let a = LoopRegion(startMeasure: 5, endMeasure: 8)
        let b = LoopRegion(startMeasure: 5, endMeasure: 8)
        let c = LoopRegion(startMeasure: 5, endMeasure: 9)
        #expect(a == b)
        #expect(a != c)
    }
}
