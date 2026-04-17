import SwiftUI
import Testing
@testable import SurVibe

struct PersistentPauseDotTests {
    @Test func rendersPauseIconWhenPlaying() {
        _ = PersistentPauseDot(
            isPlaying: true,
            backgroundColor: .black,
            foregroundColor: .white,
            onToggle: {}
        )
    }

    @Test func rendersPlayIconWhenPaused() {
        _ = PersistentPauseDot(
            isPlaying: false,
            backgroundColor: .black,
            foregroundColor: .white,
            onToggle: {}
        )
    }
}
