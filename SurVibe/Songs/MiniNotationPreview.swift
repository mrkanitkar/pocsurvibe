import SVCore
import SwiftUI

/// A compact horizontal preview of sargam notes for a song card.
///
/// Shows the first 8 note names from the song's decoded sargam notation,
/// styled in a monospaced font with subtle color coding.
///
/// Usage:
/// ```swift
/// MiniNotationPreview(song: song)
/// ```
struct MiniNotationPreview: View {
    // MARK: - Properties

    /// The song whose notation to preview.
    let song: Song

    // MARK: - Body

    var body: some View {
        // T11'-pending: was rendered from `song.decodedSargamNotes` (JSON
        // blob dropped in T5'). Will be re-implemented from `[NoteEvent]`
        // when renderers unify in T11'. For now: render nothing.
        EmptyView()
    }
}
