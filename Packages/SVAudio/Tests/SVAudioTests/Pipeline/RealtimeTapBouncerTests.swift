import AVFoundation
import Testing

@testable import SVAudio

@Suite("RealtimeTapBouncer")
@MainActor
struct RealtimeTapBouncerTests {

    @Test("Bounce produces a non-empty AAC file")
    func bounceProducesFile() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let graph = try MultiTrackSamplerGraph(trackCount: 1)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bounce_test_\(UUID().uuidString).m4a")

        let bouncer = RealtimeTapBouncer(source: graph.subMixer, outputURL: outURL)
        try bouncer.start()
        // Run the engine for a short window so the tap captures non-zero samples.
        try await Task.sleep(nanoseconds: 200_000_000)
        bouncer.stop()

        let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let size = attrs[.size] as? Int ?? 0
        #expect(size > 0, "bounce file should have non-zero size")

        try? FileManager.default.removeItem(at: outURL)
        graph.teardown()
    }

    @Test("Bounce abort deletes partial file")
    func abortDeletesPartial() throws {
        try AudioEngineManager.shared.startForPlayback()
        let graph = try MultiTrackSamplerGraph(trackCount: 1)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bounce_abort_\(UUID().uuidString).m4a")

        let bouncer = RealtimeTapBouncer(source: graph.subMixer, outputURL: outURL)
        try bouncer.start()
        bouncer.abort()

        #expect(FileManager.default.fileExists(atPath: outURL.path) == false)

        graph.teardown()
    }
}
