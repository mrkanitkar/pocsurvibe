// SurVibeTests/PianoPitchRangeTests.swift
import CoreFoundation
import Testing
@testable import SurVibe

// adaptiveMidiRange returns plain Int bounds so these tests need no Tonic import.
// CoreFoundation is imported for CGFloat literal support.

@Suite("Piano adaptive pitchRange")
struct PianoPitchRangeTests {

    @Test func below600ptReturns61Keys() {
        let (lo, hi) = InteractivePianoView.adaptiveMidiRange(
            forWidth: 400,
            whiteKeyStride: 22
        )
        #expect(lo == 36)
        #expect(hi == 96)
    }

    @Test func between600And990ptReturns73Keys() {
        let (lo, hi) = InteractivePianoView.adaptiveMidiRange(
            forWidth: 800,
            whiteKeyStride: 22
        )
        #expect(lo == 36)
        #expect(hi == 108)
    }

    @Test func above990ptReturns88Keys() {
        let (lo, hi) = InteractivePianoView.adaptiveMidiRange(
            forWidth: 1200,
            whiteKeyStride: 22
        )
        #expect(lo == 21)
        #expect(hi == 108)
    }

    @Test func breakpointsScaleWithDynamicTypeStride() {
        // Larger stride (e.g. due to Dynamic Type) shifts breakpoints
        // upward — 800pt width with stride 28 should NOT yet be 73 keys.
        let (lo, hi) = InteractivePianoView.adaptiveMidiRange(
            forWidth: 800,
            whiteKeyStride: 28
        )
        // 28 * 36 = 1008 > 800, so expect 61 keys.
        #expect(lo == 36)
        #expect(hi == 96)
    }
}
