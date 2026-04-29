import Foundation

/// Direction a note stem should be drawn.
///
/// Stems point up for notes below the middle staff line (B4, MIDI 71)
/// and down for notes on or above the middle line.
public enum StemDirection: Sendable {
    case up
    case down
}

/// Clef whose bottom-line MIDI anchors all staff position math.
///
/// `staffPosition` and friends count diatonic steps from the clef's bottom
/// line — treble = E4 (MIDI 64), bass = G2 (MIDI 43). Each clef yields its
/// own correct vertical placement directly; no post-hoc shift is needed in
/// the renderer.
public enum StaffClef: Sendable {
    /// Treble clef. Bottom line = E4 (MIDI 64), middle line = B4 (MIDI 71).
    case treble
    /// Bass clef. Bottom line = G2 (MIDI 43), middle line = D3 (MIDI 50).
    case bass

    /// MIDI number of the bottom staff line for this clef.
    var bottomLineMIDI: Int {
        switch self {
        case .treble: return 64  // E4
        case .bass: return 43    // G2
        }
    }

    /// Diatonic-position of the middle line of this clef on the
    /// 0-bottom..8-top staff coordinate system. Always 4 — both clefs are
    /// 5 lines tall — but kept named for clarity at call sites.
    var middleLinePosition: Int { 4 }
}

/// Information about ledger lines needed for a note.
///
/// Notes above or below the staff require short horizontal lines
/// to extend the staff visually. This type captures how many are
/// needed and whether they sit above or below.
public struct LedgerLineInfo: Sendable, Equatable {
    /// Number of ledger lines needed (0 if note is on the staff).
    public let count: Int

    /// Whether the ledger lines are above the staff (`true`) or below (`false`).
    public let isAbove: Bool

    /// No ledger lines needed.
    public static let none = LedgerLineInfo(count: 0, isAbove: false)
}

/// Maps MIDI note numbers to staff positions for treble clef rendering.
///
/// The treble clef staff spans from E4 (MIDI 64, bottom line) to F5
/// (MIDI 77, top line). Notes outside this range require ledger lines.
/// All calculations use diatonic (white-key) steps relative to E4 so
/// that accidentals don't shift vertical position.
///
/// ## Coordinate System
/// Staff position 0 corresponds to the bottom line (E4). Each diatonic
/// step increments the position by 1 (one half-space on the staff).
/// A standard staff has positions 0 through 8 for the five lines.
public enum StaffPositionCalculator {

    // MARK: - Constants

    /// Diatonic note names in chromatic order (C = 0).
    ///
    /// Sharps/flats map to the same diatonic position as their natural
    /// neighbor; accidental resolution is handled separately.
    private static let chromaticToDiatonic: [Int] = [
        0,  // C
        1,  // C#/Db → between C and D, maps to D position handled by accidentals
        1,  // D
        2,  // D#/Eb → maps to E-flat position
        2,  // E
        3,  // F
        3,  // F#/Gb
        4,  // G
        4,  // G#/Ab → maps to A-flat position
        5,  // A
        5,  // A#/Bb → maps to B-flat position
        6   // B
    ]

    // MARK: - Public Methods

    /// Convert a MIDI number to a diatonic step value.
    ///
    /// Diatonic steps count white-key positions from C0. This is used
    /// internally for staff position math and by `AccidentalResolver`.
    ///
    /// - Parameter midi: MIDI note number (0–127).
    /// - Returns: Diatonic step count from C0.
    static func midiToDiatonic(_ midi: Int) -> Int {
        let octave = midi / 12
        let semitone = midi % 12
        return octave * 7 + chromaticToDiatonic[semitone]
    }

    /// Calculate the staff Y-position for a given MIDI note number on the
    /// chosen clef.
    ///
    /// Position 0 is the bottom staff line of `clef` (E4 for treble, G2 for
    /// bass). Each increment moves up one half-space. The five staff lines
    /// sit at positions 0, 2, 4, 6, 8 regardless of clef.
    ///
    /// Treble examples:
    /// - C4 (60): -2 (one ledger line below the staff)
    /// - F5 (77): 8 (top line)
    /// - C6 (84): 12 (two ledger lines above)
    ///
    /// Bass examples:
    /// - C2 (36): -4 (two ledger lines below the staff)
    /// - G2 (43): 0 (bottom line)
    /// - D3 (50): 4 (middle line)
    /// - A3 (57): 8 (top line)
    /// - C4 (60): 10 (one ledger line above; this is middle C above bass)
    ///
    /// - Parameters:
    ///   - midi: MIDI note number (0–127).
    ///   - clef: Clef whose bottom line is the position-0 reference.
    ///     Defaults to `.treble` for source compatibility.
    /// - Returns: Staff position as an integer (may be negative for low notes).
    public static func staffPosition(midi: Int, clef: StaffClef = .treble) -> Int {
        let noteDiatonic = midiToDiatonic(midi)
        let referenceDiatonic = midiToDiatonic(clef.bottomLineMIDI)
        return noteDiatonic - referenceDiatonic
    }

    /// Calculate the Y offset in points for rendering on a canvas.
    ///
    /// Converts a MIDI number to a vertical pixel offset where higher
    /// notes have lower Y values (standard screen coordinates with
    /// origin at top-left).
    ///
    /// - Parameters:
    ///   - midi: MIDI note number (0–127).
    ///   - staffSpacing: Distance between adjacent staff lines in points. Default 10.
    ///   - clef: Clef whose bottom line is the position-0 reference. Defaults to `.treble`.
    /// - Returns: Y offset in points from the top staff line.
    public static func yOffset(
        midi: Int,
        staffSpacing: Double = 10.0,
        clef: StaffClef = .treble
    ) -> Double {
        let position = staffPosition(midi: midi, clef: clef)
        let halfSpace = staffSpacing / 2.0
        // Position 8 = top line, Y = 0. Position decreases → Y increases.
        let topLinePosition = 8
        return Double(topLinePosition - position) * halfSpace
    }

    /// Determine the stem direction for a note based on its staff position.
    ///
    /// Notes below the clef's middle line (position 4) get stems pointing
    /// up. Notes on or above the middle line get stems pointing down.
    ///
    /// - Parameters:
    ///   - midi: MIDI note number (0–127).
    ///   - clef: Clef context. Defaults to `.treble`.
    /// - Returns: The stem direction.
    public static func stemDirection(midi: Int, clef: StaffClef = .treble) -> StemDirection {
        let position = staffPosition(midi: midi, clef: clef)
        return position < clef.middleLinePosition ? .up : .down
    }

    /// Calculate ledger line requirements for a note.
    ///
    /// Notes with staff positions below 0 or above 8 need ledger lines.
    /// Each line corresponds to an even position outside the staff range.
    ///
    /// - Parameters:
    ///   - midi: MIDI note number (0–127).
    ///   - clef: Clef context. Defaults to `.treble`.
    /// - Returns: Ledger line information (count and direction).
    public static func ledgerLines(midi: Int, clef: StaffClef = .treble) -> LedgerLineInfo {
        let position = staffPosition(midi: midi, clef: clef)

        if position < 0 {
            // Below staff: ledger lines at positions -2, -4, -6, etc.
            // Also count position 0's line if the note is at -1
            let linesBelow = ((-position) + 1) / 2
            return LedgerLineInfo(count: linesBelow, isAbove: false)
        } else if position > 8 {
            // Above staff: ledger lines at positions 10, 12, 14, etc.
            let linesAbove = ((position - 8) + 1) / 2
            return LedgerLineInfo(count: linesAbove, isAbove: true)
        }

        return .none
    }

    /// Check whether a MIDI note sits exactly on a staff line.
    ///
    /// Staff lines are at even positions: 0, 2, 4, 6, 8.
    /// This helps renderers decide whether to draw a line through the notehead.
    ///
    /// - Parameters:
    ///   - midi: MIDI note number (0–127).
    ///   - clef: Clef context. Defaults to `.treble`.
    /// - Returns: `true` if the note sits on a line, `false` if in a space.
    public static func isOnLine(midi: Int, clef: StaffClef = .treble) -> Bool {
        let position = staffPosition(midi: midi, clef: clef)
        return position % 2 == 0
    }
}
