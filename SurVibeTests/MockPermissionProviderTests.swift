import SVCore
import Testing

@testable import SurVibe

@Suite("MockPermissionProvider Tests")
@MainActor
struct MockPermissionProviderTests {
    @Test("Default status is notDetermined")
    func defaultStatus() {
        let mock = MockPermissionProvider()
        #expect(mock.microphoneStatus == .notDetermined)
    }

    @Test("Default settingsURL is non-nil")
    func defaultSettingsURL() {
        let mock = MockPermissionProvider()
        #expect(mock.settingsURL != nil)
    }

    @Test("updateMicrophoneStatus increments call count")
    func updateMicrophoneStatusTracksCallCount() {
        let mock = MockPermissionProvider()
        #expect(mock.updateMicrophoneStatusCallCount == 0)
        mock.updateMicrophoneStatus()
        #expect(mock.updateMicrophoneStatusCallCount == 1)
        mock.updateMicrophoneStatus()
        #expect(mock.updateMicrophoneStatusCallCount == 2)
    }

    @Test("requestMicrophoneAccess returns configured result and increments call count")
    func requestMicrophoneAccessTracking() async {
        let mock = MockPermissionProvider()
        mock.requestMicrophoneAccessResult = true
        let granted = await mock.requestMicrophoneAccess()
        #expect(granted == true)
        #expect(mock.requestMicrophoneAccessCallCount == 1)
    }

    @Test("requestMicrophoneAccess returns false when configured")
    func requestMicrophoneAccessDenied() async {
        let mock = MockPermissionProvider()
        mock.requestMicrophoneAccessResult = false
        let granted = await mock.requestMicrophoneAccess()
        #expect(granted == false)
        #expect(mock.requestMicrophoneAccessCallCount == 1)
    }

    @Test("microphoneStatus can be set to any value")
    func microphoneStatusConfigurable() {
        let mock = MockPermissionProvider()
        mock.microphoneStatus = .authorized
        #expect(mock.microphoneStatus == .authorized)
        mock.microphoneStatus = .denied
        #expect(mock.microphoneStatus == .denied)
        mock.microphoneStatus = .restricted
        #expect(mock.microphoneStatus == .restricted)
    }
}
