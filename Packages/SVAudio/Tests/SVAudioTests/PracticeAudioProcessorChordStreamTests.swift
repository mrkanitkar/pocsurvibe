import Foundation
import Testing

@testable import SVAudio

// MARK: - PracticeAudioProcessor chord stream regression guards (MIN-21)

/// Tests for `PracticeAudioProcessor.chordStream` lifecycle and API surface.
///
/// `PracticeAudioProcessor.start()` requires the shared `AudioEngineManager`
/// and a real microphone tap, neither of which are available in the test
/// process. To stay deterministic, these tests cover:
/// 1. The default (un-started) chord stream API contract.
/// 2. Source-level guards that the chord stream is wired into start/stop and
///    yields only when ≥2 simultaneous pitches are detected (the MIN-21
///    documented heuristic that keeps single-note chromagram noise off the
///    stream).
@MainActor
struct PracticeAudioProcessorChordStreamTests {

    // MARK: - Default API contract

    @Test("chordStream property exists and finishes immediately when not started")
    func chordStreamFinishesImmediatelyWhenNotStarted() async {
        let processor = PracticeAudioProcessor()
        var received: [ChordResult] = []
        for await chord in processor.chordStream {
            received.append(chord)
        }
        #expect(received.isEmpty, "Un-started processor must yield no ChordResult before terminating")
    }

    @Test("lastChordResult is nil before start()")
    func lastChordResultIsNilBeforeStart() {
        let processor = PracticeAudioProcessor()
        #expect(processor.lastChordResult == nil)
    }

    @Test("isActive is false before start()")
    func isActiveIsFalseBeforeStart() {
        let processor = PracticeAudioProcessor()
        #expect(processor.isActive == false)
    }

    // MARK: - Source-level regression guards

    /// The DSP loop must yield to the chord continuation only when the analysis
    /// found two or more simultaneous pitches. This filters out the chromagram's
    /// single-note noise while monophonic input is being played.
    @Test("DSP loop gates chord yield on detectedPitches.count >= 2")
    func dspLoopGatesChordYieldOnTwoOrMorePitches() throws {
        let source = try Self.processorSource()
        #expect(source.contains("chordResult.detectedPitches.count >= 2"))
        #expect(source.contains("_chordContinuation?.yield(chordResult)"))
    }

    /// The chord stream must be created in start() and torn down in stop()
    /// alongside the existing pitch stream so consumers' `for await` loops exit
    /// cleanly on stop().
    @Test("start() creates and stop() finishes the chord continuation")
    func startCreatesAndStopFinishesChordContinuation() throws {
        let source = try Self.processorSource()
        // start() pairs makeStream() with assignment to backing storage.
        #expect(source.contains("AsyncStream<ChordResult>.makeStream()"))
        #expect(source.contains("_chordStream = chordStreamLocal"))
        #expect(source.contains("_chordContinuation = chordCont"))
        // stop() finishes and clears the backing storage.
        #expect(source.contains("_chordContinuation?.finish()"))
    }

    /// `chordStream` is a public read-only computed property returning an
    /// `AsyncStream<ChordResult>` so callers can `for await` it once start()
    /// has been called.
    @Test("chordStream is a public AsyncStream<ChordResult> property")
    func chordStreamIsPublicAsyncStream() throws {
        let source = try Self.processorSource()
        #expect(source.contains("public var chordStream: AsyncStream<ChordResult>"))
    }

    // MARK: - Helpers

    private static func processorSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceFile = testFile
            .deletingLastPathComponent()  // SVAudioTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // SVAudio/
            .appendingPathComponent("Sources/SVAudio/Practice/PracticeAudioProcessor.swift")
        return try String(contentsOf: sourceFile, encoding: .utf8)
    }
}
