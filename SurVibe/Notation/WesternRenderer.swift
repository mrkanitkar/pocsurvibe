import SwiftUI

/// Renders a horizontal sequence of Western notes with auto-scroll to the currently playing note.
///
/// Mirrors SargamRenderer's layout and geometry to enable vertical alignment
/// in dual notation mode. Uses the same baseWidth, spacing, and scroll behavior.
struct WesternRenderer: View {
    // MARK: - Properties

    /// The ordered sequence of Western notes to display.
    let notes: [WesternNote]

    /// Index of the currently playing note, or nil if playback is inactive.
    let currentNoteIndex: Int?

    /// Zoom multiplier applied to all note widths.
    let zoomScale: CGFloat

    /// MIDI note number currently pressed on the keyboard, if any.
    ///
    /// When set, the matching note block is highlighted with a green border
    /// so the user can see which notation block corresponds to the key they pressed.
    var detectedMidiNote: Int?

    /// Scoring match state of the note at `currentNoteIndex`, for a correctness overlay border.
    ///
    /// Passed to `WesternNoteView` for the active note so it can display a green or red border.
    var currentNoteMatchState: FallingNotesLayoutEngine.NoteState?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Western")
                .font(.headline)
                .padding(.horizontal, 16)

            if notes.isEmpty {
                emptyState
            } else {
                noteSequence
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Western notation display")
    }

    // MARK: - Private Views

    /// Placeholder shown when no notes are available.
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
        .accessibilityLabel("Western notation not available")
    }

    /// Horizontally scrolling note sequence with auto-scroll on index change.
    private var noteSequence: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(notes.indices, id: \.self) { index in
                        WesternNoteView(
                            note: notes[index],
                            zoomScale: zoomScale,
                            isCurrentNote: index == currentNoteIndex,
                            isPastNote: isPastNote(at: index),
                            isDetected: notes[index].midiNumber == detectedMidiNote,
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

    /// Whether the note at the given index has already been played.
    ///
    /// - Parameter index: The note index to check.
    /// - Returns: `true` if the index is before the current note index.
    private func isPastNote(at index: Int) -> Bool {
        guard let current = currentNoteIndex else { return false }
        return index < current
    }
}

// MARK: - Previews

#Preview {
    let previewNotes = [
        WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
        WesternNote(note: "D4", duration: 1.0, midiNumber: 62),
        WesternNote(note: "E4", duration: 0.5, midiNumber: 64),
        WesternNote(note: "F#4", duration: 1.0, midiNumber: 66),
        WesternNote(note: "G4", duration: 2.0, midiNumber: 67),
        WesternNote(note: "A4", duration: 1.0, midiNumber: 69),
        WesternNote(note: "B4", duration: 1.0, midiNumber: 71),
    ]

    WesternRenderer(
        notes: previewNotes,
        currentNoteIndex: 2,
        zoomScale: 1.0
    )
    .padding(16)
}
