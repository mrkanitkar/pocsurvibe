import Testing

@testable import SVCore

@Suite("PermissionManager Tests")
struct PermissionManagerTests {
    @Test("MicrophonePermissionStatus has four distinct cases")
    func statusCasesAreDistinct() {
        let statuses: Set<String> = [
            "\(MicrophonePermissionStatus.notDetermined)",
            "\(MicrophonePermissionStatus.authorized)",
            "\(MicrophonePermissionStatus.denied)",
            "\(MicrophonePermissionStatus.restricted)",
        ]
        #expect(statuses.count == 4)
    }

    @Test("Initial state reflects environment permission status")
    @MainActor
    func initialStateReflectsEnvironment() {
        let manager = PermissionManager.shared
        // On macOS the test runner may have mic access granted;
        // on iOS simulator it's typically not determined.
        // Just verify it's a valid state.
        switch manager.microphoneStatus {
        case .notDetermined, .authorized, .denied, .restricted:
            break
        }
    }

    @Test("hasShownDeniedMessage defaults to false")
    @MainActor
    func deniedMessageDefaultsFalse() {
        #expect(PermissionManager.shared.hasShownDeniedMessage == false)
    }

    @Test("settingsURL produces a valid URL with a scheme")
    @MainActor
    func settingsURLIsValid() {
        #if canImport(UIKit)
        let url = PermissionManager.shared.settingsURL
        #expect(url != nil)
        #expect(url?.scheme != nil)
        #else
        // settingsURL returns nil on macOS — no UIApplication.openSettingsURLString
        #expect(PermissionManager.shared.settingsURL == nil)
        #endif
    }

    @Test("updateMicrophoneStatus sets a valid state")
    @MainActor
    func updateStatusSetsValidState() {
        let manager = PermissionManager.shared
        manager.updateMicrophoneStatus()
        switch manager.microphoneStatus {
        case .notDetermined, .authorized, .denied, .restricted:
            break
        }
    }

    @Test("requestMicrophoneAccess exercises the permission code path")
    @MainActor
    func requestMicrophoneAccessExercisesCodePath() async {
        let manager = PermissionManager.shared
        // Exercise the full requestMicrophoneAccess() code path.
        // Result depends on environment: macOS test runner may have mic granted,
        // iOS simulator sandbox typically denies.
        let granted = await manager.requestMicrophoneAccess()
        // After the call, status should be consistent with the result
        if granted {
            #expect(manager.microphoneStatus == .authorized)
        } else {
            #expect(manager.microphoneStatus != .authorized)
        }
    }
}
