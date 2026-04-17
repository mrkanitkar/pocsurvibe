import SwiftUI
import Testing
@testable import SurVibe

struct TanpuraRagaPillTests {
    @Test func ragaModeInitializes() {
        _ = TanpuraRagaPill(
            mode: .raga(name: "Raga Yaman", tonic: "C4"),
            backgroundColor: .black,
            foregroundColor: .white
        )
    }

    @Test func westernKeyModeInitializes() {
        _ = TanpuraRagaPill(
            mode: .westernKey(key: "C major", bpm: 72),
            backgroundColor: .black,
            foregroundColor: .white
        )
    }

    @Test func popSongModeInitializes() {
        _ = TanpuraRagaPill(
            mode: .popSong(artist: "Taylor Swift", song: "Love Story"),
            backgroundColor: .white,
            foregroundColor: .purple
        )
    }
}
