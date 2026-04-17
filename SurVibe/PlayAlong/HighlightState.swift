import Foundation

/// Isolated observable that carries only MIDI key-highlight and sheet notation
/// highlight state.
///
/// ## Why a Separate Observable
/// `PlayAlongViewModel` is observed by `SongPlayAlongView`. Any write to a
/// property on that ViewModel triggers SwiftUI to re-evaluate the entire view
/// body — including `PlayAlongToolbar`, `FallingNotesView` (Canvas), and
/// `InteractivePianoView` (61 keys). The `MIDINoteHighlightCoordinator` fires
/// via `CADisplayLink` at 60–120 Hz, so if the highlight set is stored on the
/// ViewModel, `SongPlayAlongView.body` runs 60–120 times per second, keeping
/// `@MainActor` saturated and causing 300–530ms MIDI scoring lag.
///
/// By moving highlight state here, **only** the leaf views (`InteractivePianoView`
/// and `ScrollingSheetView`) observe `HighlightState`. `SongPlayAlongView.body`
/// never reads it, so display-link ticks and note-on/off events no longer
/// trigger full-hierarchy re-renders.
@Observable
@MainActor
final class HighlightState {

    /// MIDI notes currently highlighted on the piano keyboard.
    ///
    /// Written by `MIDINoteHighlightCoordinator.onActiveNotesChanged` at
    /// CADisplayLink cadence. Read only by `InteractivePianoView`.
    var midiHighlightNotes: Set<Int> = []

    /// MIDI notes to highlight as right-hand (RH color, typically blue).
    ///
    /// Written by the scoring engine as song playback progresses; read only
    /// by `InteractivePianoView`. Isolated here so the CADisplayLink-driven
    /// mutations do not re-render `SongPlayAlongView`.
    var rhNotes: Set<Int> = []

    /// MIDI notes to highlight as left-hand (LH color, typically red).
    ///
    /// Written by the scoring engine as song playback progresses; read only
    /// by `InteractivePianoView`.
    var lhNotes: Set<Int> = []

    /// MIDI notes to highlight as both hands / chord (chord color, typically purple).
    ///
    /// Takes precedence over `rhNotes` / `lhNotes` when a note appears in
    /// this set. Written by the scoring engine; read only by
    /// `InteractivePianoView`.
    var chordNotes: Set<Int> = []

    /// Swar name and octave of the first pressed MIDI/touch note, if any.
    ///
    /// Written on every note-on and note-off event. Read only by
    /// `ScrollingSheetView` (via `SargamRenderer`) so that the matching
    /// sargam block is highlighted in real time without causing
    /// `SongPlayAlongView.body` to re-evaluate.
    var detectedSwarInfo: (name: String, octave: Int)?
}
