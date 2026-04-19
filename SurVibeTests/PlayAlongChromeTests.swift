import SwiftUI
import Testing
@testable import SurVibe

struct PlayAlongChromeTests {

    @Test @MainActor func initialStateIsSummoned() {
        let vm = PlayAlongViewModel()
        #expect(vm.chromeVisibility == .summoned)
    }

    @Test @MainActor func summonChromeShowsItAndStartsTimer() {
        let vm = PlayAlongViewModel()
        vm.hideChrome()
        #expect(vm.chromeVisibility == .hidden)
        vm.summonChrome()
        #expect(vm.chromeVisibility == .summoned)
    }

    @Test @MainActor func hideChromeImmediately() {
        let vm = PlayAlongViewModel()
        vm.summonChrome()
        vm.hideChrome()
        #expect(vm.chromeVisibility == .hidden)
    }

    @Test @MainActor func autoHideWithZeroSecondsDoesNotHide() async throws {
        let vm = PlayAlongViewModel()
        vm.chromeAutoHideSeconds = 0
        vm.summonChrome()
        try await Task.sleep(for: .milliseconds(200))
        // With 0 seconds, the timer does not schedule — should remain summoned
        #expect(vm.chromeVisibility == .summoned)
    }

    @Test @MainActor func autoHideAfterInterval() async throws {
        let vm = PlayAlongViewModel()
        vm.chromeAutoHideSeconds = 0.15  // 150ms for test speed
        vm.summonChrome()
        #expect(vm.chromeVisibility == .summoned)
        // 600ms gives the auto-hide timer (150ms) ample margin under load —
        // the prior 300ms intermittently observed `.summoned` on CI.
        try await Task.sleep(for: .milliseconds(600))
        #expect(vm.chromeVisibility == .hidden)
    }

    @Test @MainActor func resetAutoHideRestartsTimer() async throws {
        let vm = PlayAlongViewModel()
        vm.chromeAutoHideSeconds = 0.2
        vm.summonChrome()
        try await Task.sleep(for: .milliseconds(100))
        vm.resetAutoHide()  // restart timer
        try await Task.sleep(for: .milliseconds(150))
        // Total elapsed 250ms; timer was reset at 100ms so should still be summoned (expires 300ms after reset).
        #expect(vm.chromeVisibility == .summoned)
    }
}
