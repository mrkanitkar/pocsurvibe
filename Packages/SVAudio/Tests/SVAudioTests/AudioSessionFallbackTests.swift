import Testing

@testable import SVAudio

@Suite("AudioSessionManager Fallback Tests")
struct AudioSessionFallbackTests {
    @Test("isMicUnavailable defaults to false")
    @MainActor
    func isMicUnavailableDefaultsFalse() {
        let manager = AudioSessionManager.shared
        #expect(manager.isMicUnavailable == false)
    }

    @Test("configure() does not crash on simulator")
    @MainActor
    func configureDoesNotCrashOnSimulator() throws {
        // On simulator, configure() should succeed without crash
        let manager = AudioSessionManager.shared
        try manager.configure()
    }

    @Test("configureForPlayback() leaves isMicUnavailable unchanged")
    @MainActor
    func configureForPlaybackLeavesFlagUnchanged() throws {
        let manager = AudioSessionManager.shared
        let before = manager.isMicUnavailable
        try manager.configureForPlayback()
        #expect(manager.isMicUnavailable == before)
    }

    @Test("sampleRate is positive after configure()")
    @MainActor
    func sampleRateAfterConfigureIsPositive() throws {
        let manager = AudioSessionManager.shared
        try manager.configure()
        #expect(manager.sampleRate > 0)
    }

    @Test("isMicUnavailable is publicly readable")
    @MainActor
    func isMicUnavailableIsPublicReadable() {
        // Verify the property is accessible (compilation test)
        let _: Bool = AudioSessionManager.shared.isMicUnavailable
    }
}
