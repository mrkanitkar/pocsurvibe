import Foundation
import Testing

@testable import SVAudio

@Suite("PitchExpression Analyzer")
@MainActor
struct PitchExpressionTests {
    /// Hop interval matching 1024 frames at 44100 Hz (~23ms).
    private let hopInterval = 1024.0 / 44100.0

    @Test func stableNoteDetected() {
        // 22 samples all near 0 cents — rock-solid intonation
        let history = Array(repeating: 1.5, count: 22)
        let result = PitchExpressionAnalyzer.analyze(
            centsHistory: history, hopIntervalSeconds: hopInterval)

        #expect(result.type == .stable)
        #expect(result.centsStdDev < 5.0)
    }

    @Test func vibratoDetected() {
        // Simulate 6 Hz vibrato with ~25-cent amplitude over ~500ms
        let history: [Double] = (0..<22).map { i in
            25.0 * sin(2.0 * .pi * 6.0 * Double(i) * hopInterval)
        }
        let result = PitchExpressionAnalyzer.analyze(
            centsHistory: history, hopIntervalSeconds: hopInterval)

        #expect(result.type == .vibrato)
        #expect(result.oscillationFrequencyHz > 4.0)
        #expect(result.oscillationFrequencyHz < 8.0)
    }

    @Test func gamakaDetected() {
        // Simulate 2 Hz oscillation with ~75-cent amplitude
        let history: [Double] = (0..<22).map { i in
            75.0 * sin(2.0 * .pi * 2.0 * Double(i) * hopInterval)
        }
        let result = PitchExpressionAnalyzer.analyze(
            centsHistory: history, hopIntervalSeconds: hopInterval)

        #expect(result.type == .gamaka)
        #expect(result.oscillationFrequencyHz > 1.0)
        #expect(result.oscillationFrequencyHz < 3.5)
    }

    @Test func meendDetected() {
        // Linear drift from -50 to +100 cents over 22 samples
        let history: [Double] = (0..<22).map { i in
            -50.0 + Double(i) * (150.0 / 21.0)
        }
        let result = PitchExpressionAnalyzer.analyze(
            centsHistory: history, hopIntervalSeconds: hopInterval)

        #expect(result.type == .meend)
        #expect(abs(result.totalDriftCents) > 80.0)
    }

    @Test func emptyHistoryReturnsIndeterminate() {
        let result = PitchExpressionAnalyzer.analyze(
            centsHistory: [], hopIntervalSeconds: hopInterval)
        #expect(result.type == .indeterminate)
    }

    @Test func shortHistoryReturnsIndeterminate() {
        let result = PitchExpressionAnalyzer.analyze(
            centsHistory: [0, 1, 2, 3, 4], hopIntervalSeconds: hopInterval)
        #expect(result.type == .indeterminate)
    }

    @Test func expressionResultEquality() {
        let result1 = ExpressionResult(type: .vibrato, centsStdDev: 15.0, oscillationFrequencyHz: 6.0)
        let result2 = ExpressionResult(type: .vibrato, centsStdDev: 15.0, oscillationFrequencyHz: 6.0)
        #expect(result1 == result2)
    }

    @Test func expressionTypeHasCorrectRawValues() {
        #expect(ExpressionType.stable.rawValue == "stable")
        #expect(ExpressionType.vibrato.rawValue == "vibrato")
        #expect(ExpressionType.meend.rawValue == "meend")
        #expect(ExpressionType.gamaka.rawValue == "gamaka")
        #expect(ExpressionType.indeterminate.rawValue == "indeterminate")
    }
}
