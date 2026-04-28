import Foundation
import Testing

@testable import SVAudio

@Suite("BundledSong")
struct BundledSongTests {

    @Test("BundledSong.all returns exactly the 2 bundled audition songs in order")
    func allReturnsTwoSongsInOrder() {
        let songs = BundledSong.all
        #expect(songs.count == 2)
        #expect(songs[0].id == "james-bond-theme")
        #expect(songs[0].displayName == "James Bond Theme")
        #expect(songs[1].id == "Sukhkarta_Dukhharta")
        #expect(songs[1].displayName == "Sukhkarta Dukhharta")
    }

    @Test("BundledSong is Hashable / Equatable / Identifiable")
    func protocolConformance() {
        let a = BundledSong(id: "x", displayName: "X")
        let b = BundledSong(id: "x", displayName: "X")
        let c = BundledSong(id: "y", displayName: "Y")
        #expect(a == b)
        #expect(a != c)
        #expect(a.id == "x")
        var seen: Set<BundledSong> = []
        seen.insert(a)
        #expect(seen.contains(b))
    }
}
