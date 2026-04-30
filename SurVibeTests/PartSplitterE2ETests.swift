import Foundation
import SVAudio
import Testing

/// End-to-end test exercising the bundled `Sukhkarta_Dukhharta.mxl` asset
/// through the full Verovio → PartSplitter pipeline.
///
/// The SVAudio package's analogous test is disabled because SPM test
/// bundles cannot read app-target resources. The asset lives at
/// `SurVibe/Diagnostics/AuditionAssets/Sukhkarta_Dukhharta.mxl`, so the
/// app test target *can* resolve it via `Bundle.main`.
@MainActor
struct PartSplitterE2ETests {

    /// Loads the bundled MXL, renders it through Verovio, runs the
    /// part splitter, and asserts the splitter selected a non-empty
    /// learner track set with at least one accompaniment instrument.
    ///
    /// This guards the production path that opens a real song and
    /// hands the result to the play-along pipeline. If the asset
    /// goes missing, the test fails loudly rather than skipping.
    @Test
    func sukhkartaDukhhartaPicksMelodyAsLearner() async throws {
        guard
            let url = Bundle.main.url(
                forResource: "Sukhkarta_Dukhharta",
                withExtension: "mxl"
            )
        else {
            Issue.record(
                "Sukhkarta_Dukhharta.mxl missing from app bundle (expected at SurVibe/Diagnostics/AuditionAssets/)."
            )
            return
        }
        let mxl = try Data(contentsOf: url)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let bridge = VerovioBridge()
        let rendered = try bridge.render(musicXML: xml)
        let split = try PartSplitter().split(rendered)
        #expect(!split.learnerTrackIndices.isEmpty)
        #expect(split.accompanimentInstruments.count >= 1)
    }
}
