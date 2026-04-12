import Testing

@testable import SVCore

@MainActor
struct SurVibeErrorTests {
    // MARK: - AudioError

    @Test
    func audioErrorDomainIsSVAudio() {
        let errors: [AudioError] = [
            .engineNotRunning,
            .engineStartFailed(underlying: "test"),
            .sessionConfigurationFailed(underlying: "test"),
            .sessionFallbackFailed(primary: "p", fallback: "f"),
            .sequencerError(underlying: "test"),
        ]
        for error in errors {
            #expect(error.domain == "SVAudio")
        }
    }

    @Test
    func audioErrorCodesAreNonEmpty() {
        let error = AudioError.engineNotRunning
        #expect(!error.code.isEmpty)
    }

    @Test
    func audioErrorDescriptionsAreNonNil() {
        let errors: [AudioError] = [
            .engineNotRunning,
            .engineStartFailed(underlying: "reason"),
            .sessionConfigurationFailed(underlying: "reason"),
            .sessionFallbackFailed(primary: "p", fallback: "f"),
            .sequencerError(underlying: "reason"),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }

    @Test
    func audioErrorAsSurVibeError() {
        let error: any SurVibeError = AudioError.engineNotRunning
        #expect(error.domain == "SVAudio")
        #expect(error.code == "engine_not_running")
    }

    // MARK: - AuthError conformance

    @Test
    func authErrorDomainIsSVCore() {
        let error = AuthError.cancelled
        #expect(error.domain == "SVCore")
        #expect(!error.code.isEmpty)
    }
}
