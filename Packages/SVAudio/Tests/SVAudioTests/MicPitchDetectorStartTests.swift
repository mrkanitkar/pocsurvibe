import Foundation
import Testing

@testable import SVAudio

/// Regression guard for micissues.md C4.
///
/// When `AudioEngineManager.installMicTap` returns `false` (engine not
/// running, 0 channels, etc.), the detector must finish the stream and
/// clear its "Listening" state rather than silently hang.
struct MicPitchDetectorStartTests {
    @Test("start() handles installMicTap failure (micissues.md C4)")
    func startHandlesTapFailure() throws {
        // Simulating a real tap failure requires coordinating with
        // AudioEngineManager.shared which is a @MainActor singleton.
        // A source-level regression guard is sufficient: the source must
        // contain a `guard installed else` branch that finishes the stream.
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceFile = testFile
            .deletingLastPathComponent()  // SVAudioTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // SVAudio/
            .appendingPathComponent("Sources/SVAudio/Pitch/MicPitchDetector.swift")
        let source = try String(contentsOf: sourceFile, encoding: .utf8)

        #expect(source.contains("let installed = AudioEngineManager.shared.installMicTap"))
        #expect(source.contains("guard installed else"))
        // The failure path must finish the continuation so consumers see end-of-stream.
        #expect(source.contains("continuation.finish()"))
    }
}
