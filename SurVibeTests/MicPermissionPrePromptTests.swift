import Foundation
import Testing

@testable import SurVibe

@MainActor
@Suite("MicPermissionPrePrompt")
struct MicPermissionPrePromptTests {

    @Test func shouldShowReturnsTrueWhenFlagAbsent() {
        UserDefaults.standard.removeObject(forKey: "hasSeenMicPermissionPrePrompt")
        #expect(MicPermissionPrePrompt.shouldShow == true)
    }

    @Test func shouldShowReturnsFalseWhenFlagSet() {
        UserDefaults.standard.set(true, forKey: "hasSeenMicPermissionPrePrompt")
        #expect(MicPermissionPrePrompt.shouldShow == false)
        UserDefaults.standard.removeObject(forKey: "hasSeenMicPermissionPrePrompt")
    }

    @Test func constructsWithEmptyCallback() {
        let view = MicPermissionPrePrompt(onContinue: {})
        _ = view
        #expect(true)
    }
}
