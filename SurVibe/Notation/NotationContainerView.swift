import SVLearning
import SwiftUI

/// Container view that manages notation display for a song.
///
/// Post-T5', the JSON-blob sargam/western note arrays were removed from
/// `Song`. Rendering from `[NoteEvent]` requires the full async
/// VerovioBridge → PartSplitter pipeline, which is deferred to a future
/// iteration. Until then, this container shows a "no notation yet"
/// placeholder so callers remain compilable without crashing or showing
/// stale data.
///
/// ## Usage
/// ```swift
/// NotationContainerView(
///     song: song,
///     currentNoteIndex: engine.currentNoteIndex,
///     labelOpacity: fadeManager.labelOpacity
/// )
/// ```
struct NotationContainerView: View {
    // MARK: - Properties

    /// The song whose notation should be displayed.
    let song: Song

    /// Index of the currently playing note, or nil if not playing.
    let currentNoteIndex: Int?

    /// Opacity for Sargam note labels, driven by ``SargamFadeManager``.
    let labelOpacity: Double

    // MARK: - Body

    var body: some View {
        NotationErrorView.noNotation
    }
}
