import SwiftUI

/// Renders a horizontal sequence of Sargam notes with auto-scroll to the currently playing note.
///
/// Uses `LazyHStack` for efficient rendering of large note sequences and
/// `ScrollViewReader` for programmatic scrolling synchronized with playback.
/// Shows an empty state message when no notation data is available.
///
/// ## Features
/// - Auto-scrolls to the current note during playback
/// - Respects `accessibilityReduceMotion` for scroll animations
/// - Past notes rendered at reduced opacity (0.5)
/// - Future notes rendered at slightly reduced opacity (0.8)
/// - Current note highlighted with scale and glow effects
/// - Detected pitch highlighted with accuracy-colored border and cents badge
struct SargamRenderer: View {

    // MARK: - Properties

    /// The ordered sequence of Sargam notes to display.
    let notes: [SargamNote]

    /// Index of the currently playing note, or nil if playback is stopped.
    let currentNoteIndex: Int?

    /// Zoom multiplier applied to all note widths. 1.0 is default.
    let zoomScale: CGFloat

    /// Opacity for note label text. Use 0.0 to hide labels entirely.
    let labelOpacity: Double

    /// Name of the currently detected pitch (e.g., "Sa", "Re"), or nil if none detected.
    var detectedNoteName: String?

    /// Octave of the currently detected pitch, or nil if none detected.
    var detectedOctave: Int?

    /// Cents offset of the currently detected pitch from the nearest note.
    var detectedCents: Double = 0

    /// Scoring match state of the note at `currentNoteIndex`, for a correctness overlay border.
    ///
    /// Passed to `SargamNoteView` for the active note so it can display a green or red border.
    var currentNoteMatchState: FallingNotesLayoutEngine.NoteState?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sargam")
                .font(.headline)
                .padding(.horizontal, 16)

            if notes.isEmpty {
                emptyState
            } else {
                noteSequence
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sargam notation display")
    }

    // MARK: - Subviews

    /// Placeholder shown when no notation data is available.
    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.headline)
                .accessibilityHidden(true)

            Text("Notation not available")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sargam notation not available")
        .accessibilityHint("No notation data has been loaded for this song")
    }

    /// The horizontally scrolling note sequence with auto-scroll behavior.
    private var noteSequence: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(notes.indices, id: \.self) { index in
                        SargamNoteView(
                            note: notes[index],
                            zoomScale: zoomScale,
                            isCurrentNote: index == currentNoteIndex,
                            isPastNote: isPastNote(at: index),
                            isDetectedNote: isNoteDetected(at: index),
                            detectedCents: isNoteDetected(at: index) ? detectedCents : 0,
                            labelOpacity: labelOpacity,
                            reduceMotion: reduceMotion,
                            matchState: index == currentNoteIndex ? currentNoteMatchState : nil
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: currentNoteIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Determines whether the note at the given index has already been played.
    ///
    /// - Parameter index: The index of the note to check.
    /// - Returns: `true` if the note is before the current playback position.
    private func isPastNote(at index: Int) -> Bool {
        guard let current = currentNoteIndex else { return false }
        return index < current
    }

    /// Determines whether the note at the given index matches the currently detected pitch.
    ///
    /// Compares the note's swar name and octave against the detected pitch values.
    ///
    /// - Parameter index: The index of the note to check.
    /// - Returns: `true` if the note matches the detected pitch.
    private func isNoteDetected(at index: Int) -> Bool {
        guard let detectedName = detectedNoteName,
              let detectedOct = detectedOctave else { return false }
        let note = notes[index]
        return note.note == detectedName && note.octave == detectedOct
    }
}

// MARK: - Previews

#Preview("With Notes") {
    let previewNotes = [
        SargamNote(note: "Sa", octave: 4, duration: 1.0),
        SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "Komal"),
        SargamNote(note: "Ga", octave: 4, duration: 0.5),
        SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "Tivra"),
        SargamNote(note: "Pa", octave: 4, duration: 2.0),
        SargamNote(note: "Dha", octave: 5, duration: 1.0),
        SargamNote(note: "Ni", octave: 5, duration: 1.0, modifier: "Komal"),
    ]

    SargamRenderer(
        notes: previewNotes,
        currentNoteIndex: 2,
        zoomScale: 1.0,
        labelOpacity: 1.0
    )
    .padding(16)
}

#Preview("Empty State") {
    SargamRenderer(
        notes: [],
        currentNoteIndex: nil,
        zoomScale: 1.0,
        labelOpacity: 1.0
    )
    .padding(16)
}

#Preview("Zoomed In") {
    let previewNotes = [
        SargamNote(note: "Sa", octave: 3, duration: 1.0),
        SargamNote(note: "Re", octave: 4, duration: 0.5),
        SargamNote(note: "Ga", octave: 4, duration: 0.25),
        SargamNote(note: "Ma", octave: 4, duration: 4.0),
        SargamNote(note: "Pa", octave: 5, duration: 1.0),
    ]

    SargamRenderer(
        notes: previewNotes,
        currentNoteIndex: 3,
        zoomScale: 1.5,
        labelOpacity: 1.0
    )
    .padding(16)
}
