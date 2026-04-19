import Foundation
import Testing
@testable import SurVibe

struct SongProgressPreferredSaHzTests {
    @Test func preferredSaHzDefaultsToNil() {
        let progress = SongProgress(songId: "yaman", songTitle: "Yaman")
        #expect(progress.preferredSaHz == nil)
    }

    @Test func preferredSaHzIsAssignable() {
        let progress = SongProgress(songId: "yaman", songTitle: "Yaman")
        progress.preferredSaHz = 277.1826
        #expect(progress.preferredSaHz == 277.1826)
    }

    @Test func preferredSaHzCanBeClearedToNil() {
        let progress = SongProgress(songId: "yaman", songTitle: "Yaman")
        progress.preferredSaHz = 300.0
        progress.preferredSaHz = nil
        #expect(progress.preferredSaHz == nil)
    }
}
