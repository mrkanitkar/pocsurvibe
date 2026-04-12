import SVLearning
import SwiftUI

// MARK: - Utility Helpers

extension StaffNotationRenderer {
    /// Convert a staff position to a Y coordinate.
    func yForStaffPosition(_ position: Int, staffTop: CGFloat) -> CGFloat {
        staffTop + CGFloat(8 - position) * (staffSpacing / 2)
    }

    /// Foreground color for current color scheme.
    var staffColor: Color { colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.85) }

    /// SwiftUI Color for text elements within the canvas.
    var staffSwiftUIColor: Color { colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.85) }
}

// MARK: - Preview

#Preview("Staff Notation - C Major") {
    StaffNotationRenderer(
        notes: [
            WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
            WesternNote(note: "D4", duration: 1.0, midiNumber: 62),
            WesternNote(note: "E4", duration: 1.0, midiNumber: 64),
            WesternNote(note: "F4", duration: 1.0, midiNumber: 65),
            WesternNote(note: "G4", duration: 1.0, midiNumber: 67),
            WesternNote(note: "A4", duration: 1.0, midiNumber: 69),
            WesternNote(note: "B4", duration: 1.0, midiNumber: 71),
            WesternNote(note: "C5", duration: 1.0, midiNumber: 72),
        ],
        currentNoteIndex: 2,
        keySignature: .cMajor,
        timeSignature: .fourFour,
        zoomScale: 1.0
    )
    .frame(height: 120)
    .padding()
}
