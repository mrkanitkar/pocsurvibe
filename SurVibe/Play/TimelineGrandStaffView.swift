// SurVibe/Play/TimelineGrandStaffView.swift
import SVCore
import SwiftUI

/// Time-aligned grand staff for the live Play tab.
///
/// Draws treble + bass staves on a single shared time axis (x = onTime),
/// so notes played simultaneously by left and right hand line up vertically
/// regardless of how many notes each hand has played. The default
/// `StaffNotationRenderer` positions notes by *array index*, which causes
/// the bass clef to "compress to the left" when only the right hand is
/// playing — this view fixes that by computing each notehead's x from
/// `RecordedNote.onTimeSec`.
///
/// Trade-offs vs. `StaffNotationRenderer`:
///
/// - No stems, beams, ties, key signature, or accidentals.
/// - Black keys render at the position of the next-lower white key
///   (no flat / sharp glyph). Acceptable for a *live preview* — the
///   formal export still produces correct notation via
///   `MusicXMLSerializer`.
/// - Notes are filled-circle noteheads (one glyph per note).
///
/// Use only for the live PlayTab strip. Saved-take playback / export uses
/// the proper renderer.
struct TimelineGrandStaffView: View {

    // MARK: - Inputs

    /// Notes to render. Should be sorted by `onTimeSec` for the cursor
    /// scan to work; the caller (`PlayTabRecordSection`) handles that.
    let notes: [RecordedNote]

    /// Current playback position in seconds (0...totalDuration). Drives the
    /// vertical playhead bar and per-note highlight. `nil` when no playback
    /// is active.
    var positionSec: TimeInterval? = nil

    /// `true` while inline take-playback is active. Used to dial up the
    /// cursor visibility (vivid green) and trigger auto-scroll-to-playhead.
    var isPlaying: Bool = false

    // MARK: - Constants

    /// Vertical spacing between adjacent staff lines, in points.
    private let lineSpacing: CGFloat = 9

    /// Horizontal pixels per second of recording. Drives the scrollable
    /// content width: a 30-second take is 30 × 80 = 2400 pt wide.
    private let pxPerSecond: CGFloat = 80

    /// Minimum content width — short recordings never collapse smaller
    /// than the viewport.
    private let minContentPx: CGFloat = 600

    /// Leading inset reserved for clef glyph + time signature.
    private let leftMargin: CGFloat = 56

    /// Trailing inset so the last note isn't flush against the edge.
    private let rightMargin: CGFloat = 24

    /// Notehead radius in points.
    private let noteheadRadiusX: CGFloat = 5
    private let noteheadRadiusY: CGFloat = 4

    /// MIDI-cutoff that splits notes between treble and bass clefs.
    private let splitMidi: Int = 60

    // MARK: - Derived

    private var totalDuration: TimeInterval {
        // Floor at 1s so an empty/very-short scratchpad doesn't divide by 0.
        max(notes.map(\.offTimeSec).max() ?? 0, 1.0)
    }

    private var contentWidth: CGFloat {
        max(minContentPx, CGFloat(totalDuration) * pxPerSecond) + leftMargin + rightMargin
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { context, size in
                    drawStaves(context: &context, size: size)
                    drawClefs(context: &context, size: size)
                    drawTimeSignature(context: &context, size: size)
                    drawNotes(context: &context, size: size)
                    drawCursor(context: &context, size: size)
                }
                .frame(width: contentWidth, height: staffSectionHeight)
                .id("canvas")
            }
            .onChange(of: positionSec ?? 0) { _, newPos in
                // Auto-scroll horizontally so the playhead stays roughly
                // centered while playing. Without this the cursor would
                // disappear off the right edge for long takes.
                guard isPlaying, totalDuration > 0 else { return }
                let frac = min(max(newPos / totalDuration, 0), 1)
                let targetX = frac
                withAnimation(.linear(duration: 0.05)) {
                    scrollProxy.scrollTo("canvas", anchor: UnitPoint(x: targetX, y: 0))
                }
            }
        }
    }

    // MARK: - Layout (private)

    private var trebleTopY: CGFloat { 30 }
    private var trebleBottomY: CGFloat { trebleTopY + lineSpacing * 4 }
    private var bassTopY: CGFloat { trebleBottomY + 48 }
    private var bassBottomY: CGFloat { bassTopY + lineSpacing * 4 }
    private var staffSectionHeight: CGFloat { bassBottomY + 30 }

    // MARK: - Drawing (private)

    private func drawStaves(context: inout GraphicsContext, size: CGSize) {
        let strokeColor = GraphicsContext.Shading.color(.primary.opacity(0.6))
        // Treble staff: 5 horizontal lines.
        for i in 0..<5 {
            let y = trebleTopY + CGFloat(i) * lineSpacing
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: strokeColor, lineWidth: 0.6)
        }
        // Bass staff: 5 horizontal lines.
        for i in 0..<5 {
            let y = bassTopY + CGFloat(i) * lineSpacing
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: strokeColor, lineWidth: 0.6)
        }
        // Vertical bar at the very start (joining the two staves like a real
        // grand staff).
        var brace = Path()
        brace.move(to: CGPoint(x: 0, y: trebleTopY))
        brace.addLine(to: CGPoint(x: 0, y: bassBottomY))
        context.stroke(brace, with: strokeColor, lineWidth: 1)
    }

    private func drawClefs(context: inout GraphicsContext, size _: CGSize) {
        let trebleClef = Text("𝄞")
            .font(.system(size: lineSpacing * 5.5, weight: .regular))
            .foregroundColor(.primary)
        context.draw(trebleClef, at: CGPoint(x: 18, y: trebleBottomY - lineSpacing * 0.4))
        let bassClef = Text("𝄢")
            .font(.system(size: lineSpacing * 3.6, weight: .regular))
            .foregroundColor(.primary)
        context.draw(bassClef, at: CGPoint(x: 18, y: bassTopY + lineSpacing * 0.6))
    }

    private func drawTimeSignature(context: inout GraphicsContext, size _: CGSize) {
        let topNum = Text("4")
            .font(.system(size: lineSpacing * 2.0, weight: .bold))
            .foregroundColor(.primary)
        let botNum = Text("4")
            .font(.system(size: lineSpacing * 2.0, weight: .bold))
            .foregroundColor(.primary)
        context.draw(topNum, at: CGPoint(x: 42, y: trebleTopY + lineSpacing))
        context.draw(botNum, at: CGPoint(x: 42, y: trebleTopY + lineSpacing * 3))
        context.draw(topNum, at: CGPoint(x: 42, y: bassTopY + lineSpacing))
        context.draw(botNum, at: CGPoint(x: 42, y: bassTopY + lineSpacing * 3))
    }

    private func drawNotes(context: inout GraphicsContext, size _: CGSize) {
        let usable = contentWidth - leftMargin - rightMargin
        for note in notes {
            let frac = TimeInterval(note.onTimeSec) / totalDuration
            let x = leftMargin + CGFloat(frac) * usable
            let isTreble = Int(note.midi) >= splitMidi
            let y: CGFloat = isTreble ? trebleY(for: Int(note.midi)) : bassY(for: Int(note.midi))
            let isCurrent = isCurrentNote(note)
            // Highlight pad behind the notehead while it's playing.
            if isCurrent {
                let pad = CGRect(
                    x: x - noteheadRadiusX - 2,
                    y: y - noteheadRadiusY - 2,
                    width: (noteheadRadiusX + 2) * 2,
                    height: (noteheadRadiusY + 2) * 2
                )
                context.fill(
                    Path(roundedRect: pad, cornerRadius: 3),
                    with: .color(.green.opacity(0.45))
                )
            }
            // Notehead.
            let head = CGRect(
                x: x - noteheadRadiusX,
                y: y - noteheadRadiusY,
                width: noteheadRadiusX * 2,
                height: noteheadRadiusY * 2
            )
            context.fill(Path(ellipseIn: head), with: .color(.primary))
            // Short stem so the notehead reads as a quarter-note.
            let stemUp = isTreble ? (Int(note.midi) < 71) : (Int(note.midi) < 50)
            var stem = Path()
            if stemUp {
                stem.move(to: CGPoint(x: x + noteheadRadiusX - 0.5, y: y))
                stem.addLine(to: CGPoint(x: x + noteheadRadiusX - 0.5, y: y - lineSpacing * 2.5))
            } else {
                stem.move(to: CGPoint(x: x - noteheadRadiusX + 0.5, y: y))
                stem.addLine(to: CGPoint(x: x - noteheadRadiusX + 0.5, y: y + lineSpacing * 2.5))
            }
            context.stroke(stem, with: .color(.primary), lineWidth: 1)
        }
    }

    private func drawCursor(context: inout GraphicsContext, size _: CGSize) {
        guard let pos = positionSec, isPlaying, totalDuration > 0 else { return }
        let usable = contentWidth - leftMargin - rightMargin
        let frac = min(max(pos / totalDuration, 0), 1)
        let x = leftMargin + CGFloat(frac) * usable
        var line = Path()
        line.move(to: CGPoint(x: x, y: trebleTopY - 6))
        line.addLine(to: CGPoint(x: x, y: bassBottomY + 6))
        context.stroke(line, with: .color(.green.opacity(0.75)), lineWidth: 2)
    }

    // MARK: - Pitch → staff Y mapping (private)

    /// White-key index per chromatic semitone: black keys map to the
    /// adjacent white key below for placement. We don't draw accidentals.
    private static let whiteKeyIdx: [Int] = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]

    /// Number of white-key staff steps above C4 (middle C). Each step is
    /// `lineSpacing/2` in pixel space.
    private func stepsAboveC4(midi: Int) -> Int {
        let octave = midi / 12 - 1
        let semitone = ((midi % 12) + 12) % 12
        return (octave - 4) * 7 + Self.whiteKeyIdx[semitone]
    }

    /// y in canvas coords for a treble-clef note. Bottom line of the treble
    /// staff is E4 (midi 64) which sits 2 white-key steps above C4.
    private func trebleY(for midi: Int) -> CGFloat {
        let stepsFromBottomLine = stepsAboveC4(midi: midi) - 2
        return trebleBottomY - CGFloat(stepsFromBottomLine) * (lineSpacing / 2)
    }

    /// y in canvas coords for a bass-clef note. Bottom line of the bass
    /// staff is G2 (midi 43) which sits 10 white-key steps below C4.
    private func bassY(for midi: Int) -> CGFloat {
        let stepsAboveBottomLine = stepsAboveC4(midi: midi) - (-10)
        return bassBottomY - CGFloat(stepsAboveBottomLine) * (lineSpacing / 2)
    }

    private func isCurrentNote(_ note: RecordedNote) -> Bool {
        guard let pos = positionSec, isPlaying else { return false }
        return note.onTimeSec <= pos && pos < note.offTimeSec
    }
}

#Preview("Empty") {
    TimelineGrandStaffView(notes: [])
        .frame(height: 220)
        .padding()
}

#Preview("C major scale, no playback") {
    let scale: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
    let notes = scale.enumerated().map { idx, midi in
        RecordedNote(
            midi: midi, velocity: 90,
            onTimeSec: TimeInterval(idx) * 0.5,
            offTimeSec: TimeInterval(idx) * 0.5 + 0.4
        )
    }
    return TimelineGrandStaffView(notes: notes)
        .frame(height: 220)
        .padding()
}

#Preview("Two-handed, mid-playback") {
    let r = (0..<8).map { idx in
        RecordedNote(midi: UInt8(60 + idx), velocity: 90,
                     onTimeSec: TimeInterval(idx) * 0.5,
                     offTimeSec: TimeInterval(idx) * 0.5 + 0.4)
    }
    let l = (0..<8).map { idx in
        RecordedNote(midi: UInt8(48 + idx), velocity: 90,
                     onTimeSec: TimeInterval(idx) * 0.5,
                     offTimeSec: TimeInterval(idx) * 0.5 + 0.4)
    }
    return TimelineGrandStaffView(notes: r + l, positionSec: 1.5, isPlaying: true)
        .frame(height: 220)
        .padding()
}
