import Foundation
import SwiftData
import Testing

@testable import SurVibe

// MARK: - Song.learnerTrackIndices Tests (Wave 4 D5)
//
// D5 closes a Wave 3 review gap: `Song.learnerTrackIndex` was a single Int
// but `PartSplit.learnerTrackIndices` returns `[Int]`. Multi-staff piano
// scores (RH + LH on separate MTrk chunks) lost their second track.
// `learnerTrackIndices: [Int]?` carries the full set; `learnerTrackIndex`
// is preserved for back-compat and mirrors `.first`.

@Suite("Song.learnerTrackIndices (Wave 4 D5)", .serialized)
@MainActor
struct SongLearnerTrackIndicesTests {

    // MARK: - Default Value

    @Test("learnerTrackIndices defaults to nil on fresh Song")
    func learnerTrackIndicesDefaultsToNil() {
        let song = Song()
        #expect(song.learnerTrackIndices == nil)
    }

    @Test("learnerTrackIndices defaults to nil with full memberwise init")
    func learnerTrackIndicesDefaultsToNilOnMemberwiseInit() {
        let song = Song(
            slugId: "fixture",
            title: "Fixture",
            artist: "Tester"
        )
        #expect(song.learnerTrackIndices == nil)
        #expect(song.learnerTrackIndex == nil)
    }

    // MARK: - Set / Read Back

    @Test("learnerTrackIndices can be set to a single-element array")
    func learnerTrackIndicesSingleElementRoundTrip() {
        let song = Song()
        song.learnerTrackIndices = [2]
        #expect(song.learnerTrackIndices == [2])
    }

    @Test("learnerTrackIndices can be set to a multi-element array")
    func learnerTrackIndicesMultiElementRoundTrip() {
        let song = Song()
        song.learnerTrackIndices = [1, 2]
        #expect(song.learnerTrackIndices == [1, 2])
    }

    @Test("learnerTrackIndices preserves source order")
    func learnerTrackIndicesPreservesOrder() {
        let song = Song()
        song.learnerTrackIndices = [3, 1, 2]
        #expect(song.learnerTrackIndices == [3, 1, 2])
    }

    @Test("learnerTrackIndices can be cleared back to nil")
    func learnerTrackIndicesClearedToNil() {
        let song = Song()
        song.learnerTrackIndices = [1, 2]
        song.learnerTrackIndices = nil
        #expect(song.learnerTrackIndices == nil)
    }

    // MARK: - SwiftData ModelContext Round-Trip

    @Test("learnerTrackIndices round-trips through SwiftData ModelContext")
    func learnerTrackIndicesRoundTripsThroughModelContext() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let song = Song(slugId: "rh-lh-fixture", title: "RH+LH", artist: "Tester")
        song.learnerTrackIndices = [1, 2]
        song.learnerTrackIndex = 1
        context.insert(song)
        try context.save()

        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.slugId == "rh-lh-fixture" }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.learnerTrackIndices == [1, 2])
        #expect(fetched.first?.learnerTrackIndex == 1)
    }
}
