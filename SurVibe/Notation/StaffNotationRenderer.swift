import SVLearning
import SwiftUI

/// Clef used by ``StaffNotationRenderer`` for staff position math and the
/// drawn clef glyph.
///
/// `staffYOffset` from `NoteLayoutEngine` is computed against treble clef's
/// bottom line (E4). For bass clef the renderer adds 12 diatonic steps so
/// G2 lands on the bass-clef bottom line, D3 on the middle line, A3 on the
/// top line — matching standard bass clef placement.
enum Clef: Sendable {
    /// Treble clef. Bottom line = E4 (MIDI 64), middle line = B4 (MIDI 71).
    case treble

    /// Bass clef. Bottom line = G2 (MIDI 43), middle line = D3 (MIDI 50).
    case bass
}

/// Canvas-based renderer for standard 5-line treble clef staff notation.
///
/// Draws a complete staff from an array of `WesternNote` values:
/// five staff lines, treble clef symbol, key signature accidentals,
/// time signature numerals, noteheads (filled/open), stems, beams,
/// flags, accidentals, ledger lines, augmentation dots, barlines,
/// and a highlight rectangle on the current note.
///
/// ## Design
/// - Receives `zoomScale` from the parent `NotationContainerView` (no own gesture).
/// - Uses `NoteLayoutEngine` for all position calculations.
/// - Adapts to dark mode via `@Environment(\.colorScheme)`.
/// - Respects reduce-motion for highlight animations.
struct StaffNotationRenderer: View {

    // MARK: - Properties

    /// Western notes to render on the staff.
    let notes: [WesternNote]

    /// Index of the currently playing note, if any.
    let currentNoteIndex: Int?

    /// Key signature for accidental resolution and display.
    let keySignature: KeySignature

    /// Time signature for measure division and display.
    let timeSignature: TimeSignature

    /// Zoom scale from the parent container.
    let zoomScale: CGFloat

    /// MIDI note number currently pressed on the keyboard, if any.
    ///
    /// When set, all noteheads matching this MIDI number are highlighted green
    /// so the user can see which staff positions correspond to the pressed key.
    var detectedMidiNote: Int?

    /// MIDI note numbers currently pressed on the keyboard, used for chord-aware
    /// live highlight on the Play tab.
    ///
    /// Combined (OR) with `detectedMidiNote` in the highlight predicate so existing
    /// single-note callers (PlayAlong, Practice) continue to work unchanged.
    var detectedMidiNotes: Set<Int> = []

    /// Scoring match state of the note at `currentNoteIndex`, for a correctness overlay border.
    ///
    /// When `.correct`, the highlight rect is drawn in green; when `.wrong`, in red.
    /// Overrides the default accent-color highlight when set.
    var currentNoteMatchState: FallingNotesLayoutEngine.NoteState?

    /// Clef to render. Defaults to `.treble` so existing call sites are
    /// unchanged. The renderer applies a per-clef offset to staff positions
    /// and re-derives stem direction and ledger-line counts from the offset
    /// position, since `NoteLayoutEngine` always emits treble-relative data.
    var clef: Clef = .treble

    // MARK: - Environment

    @Environment(\.colorScheme)
    var colorScheme
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Constants

    /// Vertical spacing between adjacent staff lines in points.
    let staffSpacing: CGFloat = 10.0

    /// Height of the staff (4 spaces × spacing).
    private var staffHeight: CGFloat { staffSpacing * 4 }

    /// Top margin above the staff for ledger lines and symbols.
    private let topMargin: CGFloat = 40.0

    /// Bottom margin below the staff.
    private let bottomMargin: CGFloat = 40.0

    /// Notehead width (horizontal diameter).
    private let noteheadWidth: CGFloat = 10.0

    /// Notehead height (vertical diameter, slightly compressed).
    private let noteheadHeight: CGFloat = 8.0

    /// Stem length in points.
    private let stemLength: CGFloat = 30.0

    /// Stem line width.
    private let stemWidth: CGFloat = 1.5

    // MARK: - Body

    var body: some View {
        let layout = computeLayout()
        let totalHeight = topMargin + staffHeight + bottomMargin

        ScrollView(.horizontal, showsIndicators: false) {
            Canvas { context, size in
                let staffTop = topMargin

                // Draw staff lines
                drawStaffLines(context: &context, staffTop: staffTop, width: size.width)

                // Draw clef symbol
                drawClef(context: &context, staffTop: staffTop)

                // Draw key signature
                drawKeySignature(context: &context, staffTop: staffTop)

                // Draw time signature
                drawTimeSignature(context: &context, staffTop: staffTop)

                // Draw barlines
                drawBarlines(context: &context, staffTop: staffTop, positions: layout.barlinePositions)

                // Draw notes
                for (index, noteInfo) in layout.notes.enumerated() {
                    let isHighlighted = index == currentNoteIndex
                    let isDetected =
                        !noteInfo.isRest
                        && (noteInfo.midiNumber == detectedMidiNote || detectedMidiNotes.contains(noteInfo.midiNumber))
                    if noteInfo.isRest {
                        drawRest(context: &context, noteInfo: noteInfo, staffTop: staffTop)
                    } else {
                        drawNote(
                            context: &context,
                            noteInfo: noteInfo,
                            staffTop: staffTop,
                            isHighlighted: isHighlighted,
                            isDetected: isDetected,
                            matchState: index == currentNoteIndex ? currentNoteMatchState : nil
                        )
                    }
                }

                // Draw beams
                for group in layout.beamGroups {
                    drawBeamGroup(context: &context, group: group, notes: layout.notes, staffTop: staffTop)
                }
            }
            .frame(width: layout.totalWidth * zoomScale, height: totalHeight * zoomScale)
            .scaleEffect(zoomScale, anchor: .topLeading)
            .frame(width: layout.totalWidth * zoomScale, height: totalHeight * zoomScale)
            .accessibilityLabel("Staff notation")
            .accessibilityHint("Sheet music display showing notes on a 5-line staff")
        }
    }

    // MARK: - Layout

    /// Compute the full note layout from the input notes.
    private func computeLayout() -> NoteLayoutResult {
        NoteLayoutEngine.layout(
            midiNumbers: notes.map(\.midiNumber),
            noteNames: notes.map(\.note),
            durations: notes.map(\.duration),
            keySignature: keySignature,
            timeSignature: timeSignature
        )
    }

    // MARK: - Staff Drawing

    /// Draw the five horizontal staff lines.
    private func drawStaffLines(context: inout GraphicsContext, staffTop: CGFloat, width: CGFloat) {
        let lineColor = staffColor
        for line in 0..<5 {
            let y = staffTop + CGFloat(line) * staffSpacing
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
        }
    }

    /// Draw the clef symbol at the left of the staff.
    private func drawClef(context: inout GraphicsContext, staffTop: CGFloat) {
        switch clef {
        case .treble:
            let text = Text("\u{1D11E}").font(.system(size: 42))
            let point = CGPoint(x: 6, y: staffTop - 12)
            context.draw(context.resolve(text), at: point, anchor: .topLeading)
        case .bass:
            // Bass clef glyph U+1D122. Sits roughly aligned with the top
            // half of the staff — anchor centre on the F3 line (position 6
            // in bass-clef-shifted coords ≈ second line from top).
            let text = Text("\u{1D122}").font(.system(size: 36))
            let point = CGPoint(x: 8, y: staffTop + staffSpacing * 0.6)
            context.draw(context.resolve(text), at: point, anchor: .topLeading)
        }
    }

    /// Draw key signature accidentals after the treble clef.
    private func drawKeySignature(context: inout GraphicsContext, staffTop: CGFloat) {
        let sharpPositions = keySignature.sharpStaffPositions
        let flatPositions = keySignature.flatStaffPositions

        var xOffset: CGFloat = 36

        for position in sharpPositions {
            let y = yForStaffPosition(position, staffTop: staffTop)
            let text = Text("\u{266F}").font(.system(size: 14)).foregroundColor(staffSwiftUIColor)
            context.draw(context.resolve(text), at: CGPoint(x: xOffset, y: y), anchor: .center)
            xOffset += 8
        }

        for position in flatPositions {
            let y = yForStaffPosition(position, staffTop: staffTop)
            let text = Text("\u{266D}").font(.system(size: 14)).foregroundColor(staffSwiftUIColor)
            context.draw(context.resolve(text), at: CGPoint(x: xOffset, y: y), anchor: .center)
            xOffset += 8
        }
    }

    /// Draw the time signature numerals.
    private func drawTimeSignature(context: inout GraphicsContext, staffTop: CGFloat) {
        let xPos: CGFloat = 55
        let topY = staffTop + staffSpacing  // Second line from top
        let bottomY = staffTop + staffSpacing * 3  // Fourth line from top

        let topText = Text("\(timeSignature.numerator)")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(staffSwiftUIColor)
        let bottomText = Text("\(timeSignature.denominator)")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(staffSwiftUIColor)

        context.draw(context.resolve(topText), at: CGPoint(x: xPos, y: topY), anchor: .center)
        context.draw(context.resolve(bottomText), at: CGPoint(x: xPos, y: bottomY), anchor: .center)
    }

    // MARK: - Note Drawing

    /// Draw a single note with all its components.
    private func drawNote(
        context: inout GraphicsContext,
        noteInfo: StaffNoteInfo,
        staffTop: CGFloat,
        isHighlighted: Bool,
        isDetected: Bool = false,
        matchState: FallingNotesLayoutEngine.NoteState? = nil
    ) {
        let centerX = noteInfo.xPosition
        let centerY = yForStaffPosition(noteInfo.staffYOffset, staffTop: staffTop)

        // Background highlights
        if isHighlighted {
            drawPlaybackHighlight(
                context: &context,
                centerX: centerX,
                centerY: centerY,
                matchState: matchState
            )
        }
        if isDetected {
            drawDetectionHighlight(
                context: &context,
                centerX: centerX,
                centerY: centerY
            )
        }

        // Ledger lines
        drawLedgerLines(context: &context, noteInfo: noteInfo, staffTop: staffTop, centerX: centerX)

        // Accidental
        drawAccidental(
            context: &context,
            noteInfo: noteInfo,
            centerX: centerX,
            centerY: centerY,
            isHighlighted: isHighlighted
        )

        // Notehead, stem, flags, augmentation dot
        let noteColor: Color = isDetected ? .green : (isHighlighted ? .accentColor : staffSwiftUIColor)
        drawNoteheadAndExtras(
            context: &context,
            noteInfo: noteInfo,
            centerX: centerX,
            centerY: centerY,
            color: noteColor
        )
    }

    /// Draw the playback highlight rectangle behind the active note.
    private func drawPlaybackHighlight(
        context: inout GraphicsContext,
        centerX: CGFloat,
        centerY: CGFloat,
        matchState: FallingNotesLayoutEngine.NoteState?
    ) {
        let highlightRect = CGRect(
            x: centerX - noteheadWidth,
            y: centerY - noteheadHeight * 2,
            width: noteheadWidth * 2,
            height: noteheadHeight * 4
        )
        let highlightColor: Color
        switch matchState {
        case .correct: highlightColor = .green.opacity(0.35)
        case .wrong: highlightColor = .red.opacity(0.35)
        default: highlightColor = .accentColor.opacity(0.2)
        }
        context.fill(
            Path(roundedRect: highlightRect, cornerRadius: 4),
            with: .color(highlightColor)
        )
    }

    /// Draw the MIDI key-press detection glow behind the notehead.
    private func drawDetectionHighlight(
        context: inout GraphicsContext,
        centerX: CGFloat,
        centerY: CGFloat
    ) {
        let detectedRect = CGRect(
            x: centerX - noteheadWidth * 1.2,
            y: centerY - noteheadHeight * 2.5,
            width: noteheadWidth * 2.4,
            height: noteheadHeight * 5
        )
        context.fill(
            Path(roundedRect: detectedRect, cornerRadius: 5),
            with: .color(.green.opacity(0.25))
        )
    }

    /// Draw the accidental symbol to the left of the notehead.
    private func drawAccidental(
        context: inout GraphicsContext,
        noteInfo: StaffNoteInfo,
        centerX: CGFloat,
        centerY: CGFloat,
        isHighlighted: Bool
    ) {
        guard let accidental = noteInfo.accidental else { return }
        let accidentalText = Text(accidental.rawValue)
            .font(.system(size: 14))
            .foregroundColor(isHighlighted ? .accentColor : staffSwiftUIColor)
        let accidentalX = centerX - noteheadWidth - 4
        context.draw(
            context.resolve(accidentalText),
            at: CGPoint(x: accidentalX, y: centerY),
            anchor: .trailing
        )
    }

    /// Draw the notehead ellipse, stem, flags, and augmentation dot.
    private func drawNoteheadAndExtras(
        context: inout GraphicsContext,
        noteInfo: StaffNoteInfo,
        centerX: CGFloat,
        centerY: CGFloat,
        color: Color
    ) {
        let noteheadRect = CGRect(
            x: centerX - noteheadWidth / 2,
            y: centerY - noteheadHeight / 2,
            width: noteheadWidth,
            height: noteheadHeight
        )
        let ellipse = Path(ellipseIn: noteheadRect)

        if noteInfo.noteheadType.isFilled {
            context.fill(ellipse, with: .color(color))
        } else {
            context.stroke(ellipse, with: .color(color), lineWidth: 1.5)
        }

        drawStemAndFlags(
            context: &context,
            noteInfo: noteInfo,
            centerX: centerX,
            centerY: centerY,
            color: color
        )

        if noteInfo.isDotted {
            let dotX = centerX + noteheadWidth / 2 + 4
            let dotY = centerY - (noteInfo.staffYOffset % 2 == 0 ? staffSpacing / 4 : 0)
            let dotRect = CGRect(x: dotX - 1.5, y: dotY - 1.5, width: 3, height: 3)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }

    /// Draw stem and optional flags for a note.
    private func drawStemAndFlags(
        context: inout GraphicsContext,
        noteInfo: StaffNoteInfo,
        centerX: CGFloat,
        centerY: CGFloat,
        color: Color
    ) {
        guard noteInfo.noteheadType.hasStem else { return }

        // Use clef-aware stem direction so bass-clef notes get the
        // correct orientation around the bass middle line (D3).
        let direction = stemDirection(forRawPosition: noteInfo.staffYOffset)
        drawStem(
            context: &context,
            centerX: centerX,
            centerY: centerY,
            direction: direction,
            color: color
        )

        // Flags for unbeamed notes only
        if noteInfo.noteheadType.beamCount == 0,
            noteInfo.noteheadType.flagCount > 0
        {
            drawFlags(
                context: &context,
                noteInfo: noteInfo,
                centerX: centerX,
                centerY: centerY,
                color: color
            )
        }
    }
}

// MARK: - Component Drawing

extension StaffNotationRenderer {
    /// Draw a rest symbol at the note's x-position.
    fileprivate func drawRest(context: inout GraphicsContext, noteInfo: StaffNoteInfo, staffTop: CGFloat) {
        let centerX = noteInfo.xPosition
        let centerY = staffTop + staffHeight / 2
        let restSymbol: String =
            switch noteInfo.noteheadType {
            case .whole: "\u{1D13B}"
            case .half: "\u{1D13C}"
            case .quarter: "\u{1D13D}"
            case .eighth: "\u{1D13E}"
            case .sixteenth: "\u{1D13F}"
            }
        let text = Text(restSymbol).font(.system(size: 24)).foregroundColor(staffSwiftUIColor)
        context.draw(context.resolve(text), at: CGPoint(x: centerX, y: centerY), anchor: .center)
    }

    /// Draw a note stem.
    fileprivate func drawStem(
        context: inout GraphicsContext,
        centerX: CGFloat,
        centerY: CGFloat,
        direction: StemDirection,
        color: Color
    ) {
        let stemX: CGFloat
        let stemStartY: CGFloat
        let stemEndY: CGFloat
        switch direction {
        case .up:
            stemX = centerX + noteheadWidth / 2 - stemWidth / 2
            stemStartY = centerY
            stemEndY = centerY - stemLength
        case .down:
            stemX = centerX - noteheadWidth / 2 + stemWidth / 2
            stemStartY = centerY
            stemEndY = centerY + stemLength
        }
        var path = Path()
        path.move(to: CGPoint(x: stemX, y: stemStartY))
        path.addLine(to: CGPoint(x: stemX, y: stemEndY))
        context.stroke(path, with: .color(color), lineWidth: stemWidth)
    }

    /// Draw flags on an unbeamed note.
    fileprivate func drawFlags(
        context: inout GraphicsContext,
        noteInfo: StaffNoteInfo,
        centerX: CGFloat,
        centerY: CGFloat,
        color: Color
    ) {
        let dir = stemDirection(forRawPosition: noteInfo.staffYOffset)
        let stemX =
            dir == .up
            ? centerX + noteheadWidth / 2 - stemWidth / 2
            : centerX - noteheadWidth / 2 + stemWidth / 2
        let stemEndY = dir == .up ? centerY - stemLength : centerY + stemLength
        for flag in 0..<noteInfo.noteheadType.flagCount {
            let off = CGFloat(flag) * 6.0
            let flagY = dir == .up ? stemEndY + off : stemEndY - off
            var p = Path()
            p.move(to: CGPoint(x: stemX, y: flagY))
            p.addQuadCurve(
                to: CGPoint(x: stemX + (dir == .up ? 8 : -8), y: flagY + (dir == .up ? 10 : -10)),
                control: CGPoint(x: stemX + (dir == .up ? 12 : -12), y: flagY + (dir == .up ? 4 : -4))
            )
            context.stroke(p, with: .color(color), lineWidth: 1.5)
        }
    }

    /// Draw ledger lines for notes above or below the staff.
    fileprivate func drawLedgerLines(
        context: inout GraphicsContext,
        noteInfo: StaffNoteInfo,
        staffTop: CGFloat,
        centerX: CGFloat
    ) {
        // Use clef-aware ledger line counts so bass-clef notes outside the
        // bass staff get the right number on the right side. The pre-computed
        // `noteInfo.ledgerLines` is treble-only.
        let info = ledgerLines(forRawPosition: noteInfo.staffYOffset)
        guard info.count > 0 else { return }  // swiftlint:disable:this empty_count
        let halfWidth = noteheadWidth * 0.8
        let lineColor = staffColor
        // Ledger-line positions are computed in clef-effective coordinates;
        // pass them through `yForStaffPosition` after un-shifting so the
        // helper applies its own shift consistently.
        for i in 0..<info.count {
            // Effective position of the i-th ledger line:
            //   above the staff: 10, 12, 14, ... (effective coordinates)
            //   below the staff: -2, -4, -6, ...
            // Convert back to raw (treble-relative) so `yForStaffPosition`
            // can re-apply the clef shift.
            let effectivePosition = info.isAbove ? 10 + (i * 2) : -2 - (i * 2)
            let rawPosition = effectivePosition - clefPositionShift
            let y = yForStaffPosition(rawPosition, staffTop: staffTop)
            var path = Path()
            path.move(to: CGPoint(x: centerX - halfWidth, y: y))
            path.addLine(to: CGPoint(x: centerX + halfWidth, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.8)
        }
    }

    /// Draw barlines at the specified x-positions.
    fileprivate func drawBarlines(context: inout GraphicsContext, staffTop: CGFloat, positions: [Double]) {
        let lineColor = staffColor
        let staffBottom = staffTop + staffHeight
        for xPos in positions {
            var path = Path()
            path.move(to: CGPoint(x: xPos, y: staffTop))
            path.addLine(to: CGPoint(x: xPos, y: staffBottom))
            context.stroke(path, with: .color(lineColor), lineWidth: 1.0)
        }
    }

    /// Draw a beam group connecting note stems.
    fileprivate func drawBeamGroup(
        context: inout GraphicsContext,
        group: BeamGroup,
        notes: [StaffNoteInfo],
        staffTop: CGFloat
    ) {
        guard group.noteIndices.count >= 2,
            let firstIdx = group.noteIndices.first, let lastIdx = group.noteIndices.last
        else { return }
        let first = notes[firstIdx]
        let last = notes[lastIdx]
        // Use clef-aware stem direction so beams render on the correct side
        // of the stems for bass-clef beam groups.
        let dir = stemDirection(forRawPosition: first.staffYOffset)
        let beamColor = staffSwiftUIColor
        let fc = yForStaffPosition(first.staffYOffset, staffTop: staffTop)
        let lc = yForStaffPosition(last.staffYOffset, staffTop: staffTop)
        for level in 0..<group.beamCount {
            let off = CGFloat(level) * 4.0
            let fx: CGFloat
            let fy: CGFloat
            let lx: CGFloat
            let ly: CGFloat
            if dir == .up {
                fx = first.xPosition + noteheadWidth / 2 - stemWidth / 2
                fy = fc - stemLength + off
                lx = last.xPosition + noteheadWidth / 2 - stemWidth / 2
                ly = lc - stemLength + off
            } else {
                fx = first.xPosition - noteheadWidth / 2 + stemWidth / 2
                fy = fc + stemLength - off
                lx = last.xPosition - noteheadWidth / 2 + stemWidth / 2
                ly = lc + stemLength - off
            }
            var p = Path()
            p.move(to: CGPoint(x: fx, y: fy))
            p.addLine(to: CGPoint(x: lx, y: ly))
            context.stroke(p, with: .color(beamColor), lineWidth: 3.0)
        }
    }
}
