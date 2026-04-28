import SVLearning
import SwiftUI
import Testing

@testable import SurVibe

/// Tests for the non-breaking `detectedMidiNotes: Set<Int>` extension to
/// `StaffNotationRenderer`.
///
/// The highlight predicate itself is private; we exercise it indirectly by
/// constructing the view with various inputs and asserting that the
/// public `detectedMidiNote` and `detectedMidiNotes` properties surface
/// the values we passed in.
struct StaffNotationRendererTests {

    @Test
    func setBasedHighlightAcceptsEmptySet() {
        let view = StaffNotationRenderer.testFixture(detectedMidiNotes: [])
        #expect(view.detectedMidiNotes.isEmpty)
        #expect(view.detectedMidiNote == nil)
    }

    @Test
    func setBasedHighlightAcceptsThreeNotes() {
        let view = StaffNotationRenderer.testFixture(detectedMidiNotes: [60, 64, 67])
        #expect(view.detectedMidiNotes == [60, 64, 67])
    }

    @Test
    func legacySingleNoteHighlightStillWorks() {
        let view = StaffNotationRenderer.testFixture(detectedMidiNote: 60)
        #expect(view.detectedMidiNote == 60)
        #expect(view.detectedMidiNotes.isEmpty)  // not mirrored
    }
}

extension StaffNotationRenderer {
    /// Test-only fixture that supplies minimal valid arguments.
    ///
    /// Keeps tests focused on the highlight props without dragging in the
    /// full notation context.
    static func testFixture(
        detectedMidiNote: Int? = nil,
        detectedMidiNotes: Set<Int> = []
    ) -> StaffNotationRenderer {
        StaffNotationRenderer(
            notes: [],
            currentNoteIndex: nil,
            keySignature: .cMajor,
            timeSignature: .fourFour,
            zoomScale: 1.0,
            detectedMidiNote: detectedMidiNote,
            detectedMidiNotes: detectedMidiNotes,
            currentNoteMatchState: nil
        )
    }
}
