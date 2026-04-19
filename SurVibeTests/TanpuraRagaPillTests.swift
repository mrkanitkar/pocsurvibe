import SwiftUI
import Testing
@testable import SurVibe

struct TanpuraRagaPillTests {
    @Test func ragaModeInitializes() {
        _ = TanpuraRagaPill(
            mode: .raga(name: "Raga Yaman"),
            saLabel: "C4",
            backgroundColor: .black,
            foregroundColor: .white
        )
    }

    @Test func westernKeyModeInitializes() {
        _ = TanpuraRagaPill(
            mode: .westernKey(key: "C major", bpm: 72),
            saLabel: "C4",
            backgroundColor: .black,
            foregroundColor: .white
        )
    }

    @Test func popSongModeInitializes() {
        _ = TanpuraRagaPill(
            mode: .popSong(artist: "Taylor Swift", song: "Love Story"),
            saLabel: "C4",
            backgroundColor: .white,
            foregroundColor: .purple
        )
    }

    @Test func onTapIsOptional() {
        var tapped = false
        _ = TanpuraRagaPill(
            mode: .raga(name: "Yaman"),
            saLabel: "C4",
            backgroundColor: .black,
            foregroundColor: .white,
            onTap: { tapped = true }
        )
        // Compile-time check: onTap parameter accepted. Runtime tap is
        // exercised via UI testing — unit test just confirms the API.
        #expect(tapped == false)
    }
}
