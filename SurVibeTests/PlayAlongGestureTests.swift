import SwiftUI
import Testing
@testable import SurVibe

/// Gesture behavior tests at the ViewModel layer.
///
/// We can't easily simulate SwiftUI gestures in unit tests, but we CAN
/// verify that the ViewModel methods the gestures invoke produce the
/// correct state transitions. Each test below mirrors the gesture
/// handler wired up in `SongPlayAlongView.contentArea`.
struct PlayAlongGestureTests {

    @Test @MainActor func tapToSummonBehavior() {
        let vm = PlayAlongViewModel()
        vm.hideChrome()
        #expect(vm.chromeVisibility == .hidden)

        // Simulating the `.onTapGesture` handler on the content area.
        vm.summonChrome()
        #expect(vm.chromeVisibility == .summoned)
    }

    @Test @MainActor func swipeDownSummonsChrome() {
        // The DragGesture handler calls summonChrome() when a downward
        // swipe is detected — same terminal state as a tap.
        let vm = PlayAlongViewModel()
        vm.hideChrome()
        vm.summonChrome()
        #expect(vm.chromeVisibility == .summoned)
    }

    @Test @MainActor func longPressSummonsForNow() {
        // For now, long-press on notation calls summonChrome().
        // (Task 2.11+ will upgrade this to open a seek scrubber.)
        let vm = PlayAlongViewModel()
        vm.hideChrome()
        vm.summonChrome()
        #expect(vm.chromeVisibility == .summoned)
    }

    @Test @MainActor func repeatedTapsResetAutoHideTimer() async throws {
        let vm = PlayAlongViewModel()
        vm.chromeAutoHideSeconds = 0.2
        vm.summonChrome()
        try await Task.sleep(for: .milliseconds(100))
        vm.summonChrome()  // tap → resets timer
        try await Task.sleep(for: .milliseconds(150))
        // 250ms total; timer reset at 100ms → should still be summoned
        // (expires 300ms after reset, i.e., 200ms from now).
        #expect(vm.chromeVisibility == .summoned)
    }
}
