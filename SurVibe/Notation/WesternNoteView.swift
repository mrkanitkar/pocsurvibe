import SwiftUI

/// Renders a single Western note as a monochrome block.
///
/// Uses the same width formula as SargamNoteView (baseWidth * duration * zoomScale)
/// to ensure vertical alignment in dual notation mode. Background is
/// `systemGray5` (auto dark mode) to avoid conflicting with Sargam colors.
struct WesternNoteView: View {
    // MARK: - Properties

    /// The Western note to render.
    let note: WesternNote

    /// Zoom multiplier applied to note width.
    let zoomScale: CGFloat

    /// Whether this note is the currently playing note.
    let isCurrentNote: Bool

    /// Whether this note has already been played.
    let isPastNote: Bool

    /// Whether the user is currently pressing this note on the keyboard.
    var isDetected: Bool = false

    /// Whether to suppress animations for accessibility.
    let reduceMotion: Bool

    /// Scoring match state of the current note for a correctness overlay border.
    ///
    /// When `.correct`, the block border turns green. When `.wrong`, it turns red.
    /// `nil` means no match state applies (upcoming/past/active notes).
    var matchState: FallingNotesLayoutEngine.NoteState?

    /// Base width in points for a quarter note (duration 1.0) at 1.0x zoom.
    private let baseWidth: CGFloat = 44.0

    // MARK: - Computed Properties

    /// Computed note width based on duration and zoom.
    private var noteWidth: CGFloat {
        baseWidth * CGFloat(note.duration) * zoomScale
    }

    /// Display name derived from the MIDI number.
    private var displayName: String {
        WesternNoteHelper.displayName(from: note.midiNumber)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            noteBlock
        }
        .frame(width: noteWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Private Views

    /// The main monochrome note block with name overlay and border.
    private var noteBlock: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isDetected ? Color.green.opacity(0.25) : Color(uiColor: .systemGray5))
            .frame(width: noteWidth, height: 48)
            .overlay(
                Text(verbatim: displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        matchState == .correct ? Color.green :
                        matchState == .wrong ? Color.red :
                        isDetected ? Color.green : Color.primary.opacity(isCurrentNote ? 1 : 0.15),
                        lineWidth: (matchState == .correct || matchState == .wrong) ? 3 :
                                   isDetected ? 2 : (isCurrentNote ? 2 : 0.5)
                    )
            )
            .if(isCurrentNote) { view in
                view
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6)
                    .scaleEffect(reduceMotion ? 1.0 : 1.15, anchor: .center)
            }
            .opacity(isPastNote ? 0.5 : (isCurrentNote ? 1.0 : 0.8))
    }

    // MARK: - Accessibility

    /// VoiceOver description combining note name, duration, and playback state.
    private var accessibilityDescription: String {
        var parts: [String] = [displayName]

        switch note.duration {
        case 0.25: parts.append("sixteenth note")
        case 0.5: parts.append("eighth note")
        case 1.0: parts.append("quarter note")
        case 2.0: parts.append("half note")
        case 4.0: parts.append("whole note")
        default: parts.append("note")
        }

        if isCurrentNote {
            parts.append("currently playing")
        }
        if isDetected {
            parts.append("key pressed")
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Current Note") {
    WesternNoteView(
        note: WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
        zoomScale: 1.0,
        isCurrentNote: true,
        isPastNote: false,
        reduceMotion: false
    )
    .padding()
}

#Preview("Past Note") {
    WesternNoteView(
        note: WesternNote(note: "D#3", duration: 0.5, midiNumber: 51),
        zoomScale: 1.0,
        isCurrentNote: false,
        isPastNote: true,
        reduceMotion: false
    )
    .padding()
}
