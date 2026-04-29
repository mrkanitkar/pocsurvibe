import SVLearning
import SwiftUI

// MARK: - Utility Helpers

extension StaffNotationRenderer {
    /// Convert a clef-relative staff position to a Y coordinate.
    ///
    /// Position 0 = clef's bottom line (E4 for treble, G2 for bass) — this
    /// is what `NoteLayoutEngine` now emits when given the same `clef`. No
    /// post-hoc shift needed.
    func yForStaffPosition(_ position: Int, staffTop: CGFloat) -> CGFloat {
        staffTop + CGFloat(8 - position) * (staffSpacing / 2)
    }

    /// Stem direction for a note at the given clef-relative staff position.
    ///
    /// Stems point up below the middle line (position 4) and down on/above
    /// it. The pre-computed `noteInfo.stemDirection` is already correct for
    /// the active clef; this helper exists for ledger-line / beam paths
    /// that work in raw position space.
    func stemDirection(forRawPosition position: Int) -> StemDirection {
        position < 4 ? .up : .down
    }

    /// Ledger lines for a note at the given clef-relative staff position.
    ///
    /// SVLearning's `LedgerLineInfo` initializer is internal so the renderer
    /// returns a plain tuple. Since `NoteLayoutEngine` now emits positions
    /// already anchored to the active clef, this helper just inspects the
    /// raw position directly.
    func ledgerLines(forRawPosition position: Int) -> (count: Int, isAbove: Bool) {
        if position < 0 {
            return (count: ((-position) + 1) / 2, isAbove: false)
        }
        if position > 8 {
            return (count: ((position - 8) + 1) / 2, isAbove: true)
        }
        return (count: 0, isAbove: false)
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
