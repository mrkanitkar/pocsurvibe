import SwiftUI
import Testing
@testable import SurVibe

struct PersistentPauseDotTests {
    @Test func rendersPauseIconWhenPlaying() {
        _ = PersistentPauseDot(
            isPlaying: true,
            foregroundColor: .white,
            onToggle: {}
        )
    }

    @Test func rendersPlayIconWhenPaused() {
        _ = PersistentPauseDot(
            isPlaying: false,
            foregroundColor: .white,
            onToggle: {}
        )
    }
}
