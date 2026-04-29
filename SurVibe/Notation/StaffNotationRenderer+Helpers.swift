import SVLearning
import SwiftUI

// MARK: - Utility Helpers

extension StaffNotationRenderer {
    /// Diatonic-step shift to apply to a treble-relative `staffYOffset` so
    /// it lands at the correct position for the active clef.
    ///
    /// `NoteLayoutEngine` always emits positions with `0 = E4` (treble bottom
    /// line). Bass clef's bottom line is G2, which is exactly 12 diatonic
    /// steps below E4 — adding 12 puts G2 at position 0 in bass clef.
    var clefPositionShift: Int {
        switch clef {
        case .treble: return 0
        case .bass: return 12
        }
    }

    /// Convert a staff position (treble-relative as emitted by SVLearning)
    /// to a Y coordinate, applying the clef's positional shift so bass-clef
    /// notes render at correct positions on a bass-clef staff.
    func yForStaffPosition(_ position: Int, staffTop: CGFloat) -> CGFloat {
        let effective = position + clefPositionShift
        return staffTop + CGFloat(8 - effective) * (staffSpacing / 2)
    }

    /// Stem direction for a note at the given treble-relative staff position.
    ///
    /// Stems point up below the middle line and down on/above it. The
    /// pre-computed `noteInfo.stemDirection` from SVLearning is correct for
    /// treble clef only; this helper re-evaluates against the clef-shifted
    /// effective position so bass-clef notes get the right stem direction.
    func stemDirection(forRawPosition position: Int) -> StemDirection {
        let effective = position + clefPositionShift
        return effective < 4 ? .up : .down
    }

    /// Ledger lines for a note at the given treble-relative staff position.
    ///
    /// SVLearning's `LedgerLineInfo` initializer is internal so the renderer
    /// returns a plain tuple. For treble clef this is a no-op shim around
    /// the shipped value; for bass clef we re-derive against the
    /// clef-shifted position so bass-staff notes show the correct ledger
    /// lines on the correct side.
    func ledgerLines(forRawPosition position: Int) -> (count: Int, isAbove: Bool) {
        let effective = position + clefPositionShift
        if effective < 0 {
            return (count: ((-effective) + 1) / 2, isAbove: false)
        }
        if effective > 8 {
            return (count: ((effective - 8) + 1) / 2, isAbove: true)
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
