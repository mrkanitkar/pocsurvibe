import SwiftUI

/// Grand-staff notation renderer with horizontal colored bars.
///
/// Used by Immersive Bars (#6), Midnight Bars (#7), and Pop Era (#9) themes.
/// Each bar's Y position encodes pitch, width encodes duration, color encodes
/// the performing hand (RH blue / LH red / both purple).
///
/// ## Latency contract
/// All colors arrive as `let` parameters. This view MUST NOT read
/// `@Environment(AppThemeManager.self)` — doing so would trigger 120Hz
/// re-renders from the CADisplayLink highlight path, violating the 3-10ms
/// audio-latency guarantee.
struct BarsOnStaffView: View {
    let noteEvents: [NoteEvent]
    let currentTime: TimeInterval
    let rhColor: Color
    let lhColor: Color
    let chordColor: Color
    let notationLineColor: Color
    let notationSecondaryColor: Color
    let showTrebleClef: Bool
    let showBassClef: Bool

    /// Seconds of lookahead visible on screen to the right of the playhead.
    private let windowSeconds: TimeInterval = 4.0

    /// Playhead's normalized X position (0..1) within the drawing area.
    private let playheadXFraction: CGFloat = 0.28

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                drawStaff(ctx: ctx, size: size)
                drawBars(ctx: ctx, size: size)
                drawPlayhead(ctx: ctx, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Grand staff notation with \(noteEvents.count) notes")
    }

    // MARK: - Staff

    /// Draw the horizontal staff lines for the treble and/or bass clef and the
    /// joining barline when both clefs are visible.
    private func drawStaff(ctx: GraphicsContext, size: CGSize) {
        let trebleTopY = size.height * 0.10
        let bassTopY = size.height * 0.55
        let lineSpacing = size.height * 0.04
        let leftMargin: CGFloat = 40
        let rightMargin: CGFloat = 10

        if showTrebleClef {
            for i in 0..<5 {
                let y = trebleTopY + CGFloat(i) * lineSpacing
                var path = Path()
                path.move(to: CGPoint(x: leftMargin, y: y))
                path.addLine(to: CGPoint(x: size.width - rightMargin, y: y))
                ctx.stroke(path, with: .color(notationLineColor), lineWidth: 1.2)
            }
        }
        if showBassClef {
            for i in 0..<5 {
                let y = bassTopY + CGFloat(i) * lineSpacing
                var path = Path()
                path.move(to: CGPoint(x: leftMargin, y: y))
                path.addLine(to: CGPoint(x: size.width - rightMargin, y: y))
                ctx.stroke(path, with: .color(notationLineColor), lineWidth: 1.2)
            }
        }
        if showTrebleClef && showBassClef {
            // Brace connecting both staves
            var barline = Path()
            barline.move(to: CGPoint(x: leftMargin, y: trebleTopY))
            barline.addLine(to: CGPoint(x: leftMargin, y: bassTopY + 4 * lineSpacing))
            ctx.stroke(barline, with: .color(notationLineColor), lineWidth: 1.5)
        }
    }

    // MARK: - Bars

    /// Draw one rounded rectangle per `NoteEvent` visible within the current
    /// scroll window. Bars outside the window are skipped for performance.
    private func drawBars(ctx: GraphicsContext, size: CGSize) {
        let playheadX = playheadXFraction * size.width
        let pixelsPerSecond = (size.width - playheadX - 20) / CGFloat(windowSeconds)
        let chordGroups = chordGroupings()

        for event in noteEvents {
            let startX = playheadX + CGFloat(event.timestamp - currentTime) * pixelsPerSecond
            let barWidth = max(4, CGFloat(event.duration) * pixelsPerSecond)
            if startX + barWidth < 0 || startX > size.width { continue }

            let color: Color = {
                // If this event belongs to a chord group active at the current beat,
                // render chord color.
                if chordGroups.contains(where: { group in
                    group.contains(event.id) && chordActiveAtTime(group: group, time: currentTime)
                }) {
                    return chordColor
                }
                return event.hand == .right ? rhColor : lhColor
            }()
            let y = yForMidiNote(Int(event.midiNote), size: size)
            let rect = CGRect(x: startX, y: y, width: barWidth, height: 14)
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(color)
            )
            ctx.stroke(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(.white.opacity(0.5)),
                lineWidth: 0.5
            )
        }
    }

    /// Group events whose start times fall within 10ms of each other.
    ///
    /// These simultaneous events are candidates for chord bracketing — when a
    /// group of 2+ notes shares a start time, the overlay renderer treats them
    /// as a single chord and recolors them with `chordColor`.
    private func chordGroupings() -> [[UUID]] {
        // Group events that share the same timestamp (within 10ms).
        let sorted = noteEvents.sorted(by: { $0.timestamp < $1.timestamp })
        var groups: [[UUID]] = []
        var current: [NoteEvent] = []
        for event in sorted {
            if let first = current.first, abs(event.timestamp - first.timestamp) < 0.01 {
                current.append(event)
            } else {
                if current.count >= 2 { groups.append(current.map(\.id)) }
                current = [event]
            }
        }
        if current.count >= 2 { groups.append(current.map(\.id)) }
        return groups
    }

    /// Whether the given chord group is active at `time` (i.e., the first note
    /// of the group has started and has not yet ended).
    private func chordActiveAtTime(group: [UUID], time: TimeInterval) -> Bool {
        guard let first = noteEvents.first(where: { group.contains($0.id) }) else { return false }
        return time >= first.timestamp && time <= (first.timestamp + first.duration)
    }

    // MARK: - Playhead

    /// Draw the vertical white playhead line.
    private func drawPlayhead(ctx: GraphicsContext, size: CGSize) {
        let x = playheadXFraction * size.width
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(path, with: .color(.white), lineWidth: 2)
    }

    // MARK: - Pitch mapping

    /// Map a MIDI note number (36..84 = C2..C6) to a Y coordinate. Higher MIDI
    /// numbers map to smaller Y values (higher on screen). Values outside the
    /// piano-relevant range are clamped.
    private func yForMidiNote(_ midi: Int, size: CGSize) -> CGFloat {
        // Map MIDI 36 (C2) → 84 (C6) to vertical space, inverted
        // (higher MIDI = higher pixel-wise = smaller Y).
        let clamped = max(36, min(84, midi))
        let normalized = CGFloat(84 - clamped) / CGFloat(84 - 36)
        return size.height * 0.10 + normalized * size.height * 0.75
    }
}

#Preview("Empty staff") {
    BarsOnStaffView(
        noteEvents: [],
        currentTime: 0,
        rhColor: .blue,
        lhColor: .red,
        chordColor: .purple,
        notationLineColor: .black,
        notationSecondaryColor: .gray,
        showTrebleClef: true,
        showBassClef: true
    )
    .frame(width: 800, height: 400)
    .background(Color.white)
}
