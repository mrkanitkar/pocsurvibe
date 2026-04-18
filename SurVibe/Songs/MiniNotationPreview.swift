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

    @Environment(AppThemeManager.self) private var themeManager

    /// The song whose notation to preview.
    let song: Song

    /// Maximum number of notes to display.
    private let maxNotes = 8

    // MARK: - Body

    var body: some View {
        if let notes = song.decodedSargamNotes, !notes.isEmpty {
            HStack(spacing: 4) {
                let displayNotes = Array(notes.prefix(maxNotes))

                ForEach(displayNotes.indices, id: \.self) { index in
                    noteText(displayNotes[index])
                }

                if notes.count > maxNotes {
                    Text(verbatim: "...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notationAccessibilityLabel)
        }
    }

    // MARK: - Private Methods

    /// Styled text for a single sargam note.
    ///
    /// - Parameter note: The sargam note to display.
    /// - Returns: A styled text view.
    private func noteText(_ note: SargamNote) -> some View {
        Text(verbatim: noteLabel(note))
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.medium)
            .foregroundStyle(noteColor(note))
    }

    /// Short label for a note (e.g., "Sa", "Re♭").
    ///
    /// - Parameter note: The sargam note.
    /// - Returns: A compact display string.
    private func noteLabel(_ note: SargamNote) -> String {
        var label = note.note
        if let modifier = note.modifier {
            switch modifier {
            case "komal":
                label += "\u{266D}"  // ♭
            case "tivra":
                label += "\u{266F}"  // ♯
            default:
                break
            }
        }
        return label
    }

    /// Color for a note based on its position in the sargam scale.
    ///
    /// Uses the Rang color system (`Color.rang*` from SVCore) for
    /// consistent sargam note differentiation across the app.
    ///
    /// - Parameter note: The sargam note.
    /// - Returns: A color for visual differentiation.
    private func noteColor(_ note: SargamNote) -> Color {
        switch note.note {
        case "Sa": themeManager.resolved.notationLineColor
        case "Re": .rangNeel
        case "Ga": .rangHara
        case "Ma": .rangPeelaDark
        case "Pa": themeManager.resolved.notationLineColor
        case "Dha": .rangLal
        case "Ni": .rangSonaDark
        default: themeManager.resolved.notationSecondaryColor
        }
    }

    /// Accessibility label for the notation preview.
    private var notationAccessibilityLabel: Text {
        guard let notes = song.decodedSargamNotes, !notes.isEmpty else {
            return Text("No notation available")
        }
        let noteNames = notes.prefix(maxNotes).map { noteLabel($0) }.joined(separator: ", ")
        return Text("Sargam notation preview: \(noteNames)")
    }
}
