import SwiftUI

/// Renders a single Sargam note as a colored block with modifier and octave markers.
///
/// Width is proportional to the note's duration multiplied by the zoom scale.
/// Visual treatment varies based on whether the note is currently playing,
/// has already been played, or is upcoming.
///
/// ## Layout
/// - Tivra modifier: thin line above the note block
/// - Main block: colored rectangle with rounded corners
/// - Komal modifier: dot below the note block
/// - Note label: swar name text below
/// - Octave marker: dot below (mandra/octave 3) or above (taar/octave 5),
///   none for madhya (octave 4)
struct SargamNoteView: View {

    // MARK: - Properties

    /// The Sargam note data to render.
    let note: SargamNote

    /// Zoom multiplier applied to note width. 1.0 is default size.
    let zoomScale: CGFloat

    /// Whether this note is the one currently being played.
    let isCurrentNote: Bool

    /// Whether this note has already been played in the sequence.
    let isPastNote: Bool

    /// Whether this note matches the currently detected pitch from the microphone.
    var isDetectedNote: Bool = false

    /// Cents offset of the detected pitch (only meaningful when `isDetectedNote` is true).
    var detectedCents: Double = 0

    /// Opacity for the note label text below the block.
    let labelOpacity: Double

    /// Whether the user has enabled reduced motion in accessibility settings.
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

    /// Background color for this swar.
    private var backgroundColor: Color {
        SargamColorMap.color(for: note.note)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            octaveAboveMarker
            tivraMarker
            noteBlock
            komalMarker
            noteLabel
            octaveBelowMarker
        }
        .frame(width: noteWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    /// Tivra modifier indicator: a thin horizontal line above the note block.
    @ViewBuilder
    private var tivraMarker: some View {
        if note.modifier == "Tivra" {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary)
                .frame(width: noteWidth - 8, height: 1.5)
                .opacity(0.6)
        }
    }

    /// The main colored rectangle representing the note.
    private var noteBlock: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .frame(width: noteWidth, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(noteStrokeColor, lineWidth: noteStrokeWidth)
            )
            .overlay(alignment: .topTrailing) {
                // Cents badge when this note is detected
                if isDetectedNote {
                    centsBadge
                }
            }
            .if(isCurrentNote) { view in
                view
                    .shadow(color: backgroundColor.opacity(0.6), radius: 8)
                    .scaleEffect(reduceMotion ? 1.0 : 1.15, anchor: .center)
            }
            .if(isDetectedNote && !isCurrentNote) { view in
                view
                    .shadow(color: detectionAccuracyColor.opacity(0.5), radius: 6)
            }
            .opacity(isPastNote ? 0.5 : (isCurrentNote ? 1.0 : 0.8))
    }

    /// Stroke color for the note block border.
    ///
    /// Priority: match state (green/red) > detected pitch accuracy > current/past note default.
    private var noteStrokeColor: Color {
        if matchState == .correct { return .green }
        if matchState == .wrong { return .red }
        if isDetectedNote {
            return detectionAccuracyColor
        }
        return Color.primary.opacity(isCurrentNote ? 1 : 0.2)
    }

    /// Stroke width for the note block border.
    private var noteStrokeWidth: CGFloat {
        if matchState == .correct || matchState == .wrong { return 3 }
        if isDetectedNote { return 3 }
        return isCurrentNote ? 2 : 0.5
    }

    /// Compact cents offset badge overlaid on detected notes.
    private var centsBadge: some View {
        Text(centsLabel)
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Capsule().fill(detectionAccuracyColor))
            .offset(x: 4, y: -4)
            .accessibilityHidden(true)
    }

    /// Formatted cents label (e.g., "+5¢" or "−12¢").
    private var centsLabel: String {
        let rounded = Int(detectedCents)
        if abs(rounded) < 5 { return "✓" }
        return "\(rounded > 0 ? "+" : "")\(rounded)¢"
    }

    /// Color indicating pitch accuracy of the detected note.
    private var detectionAccuracyColor: Color {
        let absCents = abs(detectedCents)
        if absCents < 10 { return .green }
        if absCents < 25 { return .orange }
        return .red
    }

    /// Komal modifier indicator: a small dot below the note block.
    @ViewBuilder
    private var komalMarker: some View {
        if note.modifier == "Komal" {
            Circle()
                .fill(Color.primary)
                .frame(width: 6, height: 6)
                .opacity(0.6)
        }
    }

    /// The swar name label displayed below the note block.
    private var noteLabel: some View {
        Text(verbatim: note.note)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: noteWidth)
            .lineLimit(1)
            .opacity(labelOpacity)
    }

    /// Dot above the note block indicating taar saptak (octave 5).
    @ViewBuilder
    private var octaveAboveMarker: some View {
        if note.octave == 5 {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
        }
    }

    /// Dot below the note label indicating mandra saptak (octave 3).
    @ViewBuilder
    private var octaveBelowMarker: some View {
        if note.octave == 3 {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
        }
    }

    // MARK: - Accessibility

    /// VoiceOver description combining note name, octave, modifier, duration, and playing state.
    private var accessibilityDescription: String {
        var parts: [String] = [note.note]

        switch note.octave {
        case 3: parts.append("low octave")
        case 4: parts.append("middle octave")
        case 5: parts.append("high octave")
        default: break
        }

        if let modifier = note.modifier {
            parts.append(modifier.lowercased())
        }

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
        if isDetectedNote {
            let absCents = abs(Int(detectedCents))
            if absCents < 10 {
                parts.append("detected, in tune")
            } else {
                let direction = detectedCents > 0 ? "sharp" : "flat"
                parts.append("detected, \(absCents) cents \(direction)")
            }
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Current Note") {
    SargamNoteView(
        note: SargamNote(note: "Sa", octave: 4, duration: 1.0),
        zoomScale: 1.0,
        isCurrentNote: true,
        isPastNote: false,
        labelOpacity: 1.0,
        reduceMotion: false
    )
    .padding()
}

#Preview("Komal Modifier") {
    SargamNoteView(
        note: SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "Komal"),
        zoomScale: 1.0,
        isCurrentNote: false,
        isPastNote: false,
        labelOpacity: 1.0,
        reduceMotion: false
    )
    .padding()
}

#Preview("Tivra Modifier") {
    SargamNoteView(
        note: SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "Tivra"),
        zoomScale: 1.0,
        isCurrentNote: false,
        isPastNote: false,
        labelOpacity: 1.0,
        reduceMotion: false
    )
    .padding()
}

#Preview("Mandra Saptak") {
    SargamNoteView(
        note: SargamNote(note: "Pa", octave: 3, duration: 2.0),
        zoomScale: 1.0,
        isCurrentNote: false,
        isPastNote: true,
        labelOpacity: 1.0,
        reduceMotion: false
    )
    .padding()
}

#Preview("Taar Saptak") {
    SargamNoteView(
        note: SargamNote(note: "Dha", octave: 5, duration: 0.5),
        zoomScale: 1.0,
        isCurrentNote: false,
        isPastNote: false,
        labelOpacity: 1.0,
        reduceMotion: false
    )
    .padding()
}
