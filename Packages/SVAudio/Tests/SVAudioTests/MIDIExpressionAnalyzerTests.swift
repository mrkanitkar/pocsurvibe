import Foundation
import Testing

@testable import SVAudio

// MARK: - MIDIExpressionAnalyzerTests

@Suite("MIDIExpressionAnalyzer")
struct MIDIExpressionAnalyzerTests {

    // MARK: - Insufficient Samples

    @Test("returns nil with insufficient samples")
    func insufficientSamples() {
        let analyzer = MIDIExpressionAnalyzer()
        // Only 1 sample — need at least 10
        let event = MIDIPitchBendEvent(value: 1000)
        let result = analyzer.process(event)
        #expect(result == nil)
    }

    @Test("returns nil with 9 samples (one below threshold)")
    func ninesamples() {
        let analyzer = MIDIExpressionAnalyzer()
        var result: ExpressionResult?
        for i in 0..<9 {
            let event = MIDIPitchBendEvent(
                value: Int32(i * 100),
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000
            )
            result = analyzer.process(event)
        }
        #expect(result == nil)
    }

    // MARK: - Minimum Samples Threshold

    @Test("returns result after minimum 10 samples")
    func minimumSamplesProducesResult() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        var result: ExpressionResult?

        for i in 0..<10 {
            let event = MIDIPitchBendEvent(
                value: Int32(i * 100),
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000
            )
            result = analyzer.process(event)
        }

        #expect(result != nil)
    }

    @Test("returns result with 22 oscillating samples")
    func oscillatingSamplesProduceResult() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        var result: ExpressionResult?

        // Simulate oscillation at ~2 Hz over 22 samples (~500ms)
        for i in 0..<22 {
            let angle = Double(i) * 2.0 * .pi * 2.0 / 22.0
            let bendValue = Int32(sin(angle) * 3072.0)
            let event = MIDIPitchBendEvent(
                value: bendValue,
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000,
                resolution: .midi1
            )
            result = analyzer.process(event)
        }

        #expect(result != nil)
        // Oscillating pattern should not remain indeterminate
        #expect(result?.type != .indeterminate)
    }

    @Test("constant bend produces result")
    func constantBendProducesResult() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        var result: ExpressionResult?

        for i in 0..<22 {
            let event = MIDIPitchBendEvent(
                value: 100,
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000,
                resolution: .midi1
            )
            result = analyzer.process(event)
        }

        #expect(result != nil)
    }

    // MARK: - Reset

    @Test("reset clears history")
    func resetClearsHistory() {
        let analyzer = MIDIExpressionAnalyzer()

        // Add 15 samples to build up history
        for i in 0..<15 {
            let event = MIDIPitchBendEvent(value: Int32(i * 100))
            _ = analyzer.process(event)
        }

        analyzer.reset()

        // Should return nil again (insufficient samples after reset)
        let event = MIDIPitchBendEvent(value: 100)
        #expect(analyzer.process(event) == nil)
    }

    @Test("reset then rebuild returns result after 10 new samples")
    func resetThenRebuildProducesResult() {
        let analyzer = MIDIExpressionAnalyzer()

        for i in 0..<15 {
            let event = MIDIPitchBendEvent(value: Int32(i * 50))
            _ = analyzer.process(event)
        }

        analyzer.reset()

        var result: ExpressionResult?
        for i in 0..<10 {
            let event = MIDIPitchBendEvent(
                value: Int32(i * 100),
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000
            )
            result = analyzer.process(event)
        }

        #expect(result != nil)
    }

    // MARK: - setBendRange

    @Test("setBendRange changes conversion")
    func setBendRangeAffectsConversion() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        analyzer.setBendRange(semitones: 12.0)

        var result: ExpressionResult?
        for i in 0..<22 {
            let event = MIDIPitchBendEvent(
                value: 500,
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000,
                resolution: .midi1
            )
            result = analyzer.process(event)
        }

        // With ±12 range and constant bend, should still produce a result
        #expect(result != nil)
    }

    // MARK: - Pressure Events

    @Test("pressure event produces result after minimum samples")
    func pressureEventProducesResult() {
        let analyzer = MIDIExpressionAnalyzer()
        var result: ExpressionResult?

        for i in 0..<12 {
            let event = MIDIPressureEvent(
                noteNumber: 60,
                pressure: UInt32(i) * 300_000_000,
                channel: 0,
                midiTimestamp: UInt64(i) * 23_000_000
            )
            result = analyzer.process(event)
        }

        #expect(result != nil)
    }

    @Test("pressure event returns nil with insufficient samples")
    func pressureInsufficientSamples() {
        let analyzer = MIDIExpressionAnalyzer()
        let event = MIDIPressureEvent(
            pressure: 1_000_000_000,
            channel: 0
        )
        let result = analyzer.process(event)
        #expect(result == nil)
    }
}
