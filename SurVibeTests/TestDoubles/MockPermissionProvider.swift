import SVCore

/// Mock permission provider for testing microphone permission flows.
///
/// Tracks call counts and returns configurable results for permission requests.
@MainActor
final class MockPermissionProvider: PermissionProviding {
    /// Current microphone permission status. Default: `.notDetermined`.
    var microphoneStatus: MicrophonePermissionStatus = .notDetermined

    /// URL to the app's Settings page. Default: a dummy URL.
    var settingsURL: URL? = URL(string: "app-settings://")

    /// What `requestMicrophoneAccess()` returns. Default: `true`.
    var requestMicrophoneAccessResult: Bool = true

    /// Number of times `updateMicrophoneStatus()` was called.
    var updateMicrophoneStatusCallCount = 0

    /// Number of times `requestMicrophoneAccess()` was called.
    var requestMicrophoneAccessCallCount = 0

    func updateMicrophoneStatus() {
        updateMicrophoneStatusCallCount += 1
    }

    func requestMicrophoneAccess() async -> Bool {
        requestMicrophoneAccessCallCount += 1
        return requestMicrophoneAccessResult
    }
}
