import SwiftUI

/// Canvas-based falling notes visualization for play-along mode.
///
/// Notes descend from the top of the viewport toward a "hit line" near the
/// bottom, aligned horizontally with the piano keyboard below. Uses `Canvas`
/// for efficient GPU-accelerated rendering of potentially hundreds of notes,
/// avoiding the overhead of individual SwiftUI views per note.
///
/// ## Layout Coordinate System
/// - Y = 0 is the top of the viewport (far future notes).
/// - Y = viewportHeight is the bottom (hit line / current playback position).
/// - X positions are derived from `KeyPosition` data reported by the piano keyboard.
///
/// ## Performance
/// Only notes passing the `isNoteVisible` culling check are drawn.
/// `TimelineView(.animation)` drives smooth 60 fps updates during playback.
///
/// ## Accessibility
/// When `accessibilityReduceMotion` is enabled, notes are drawn without
/// the animated glow effect on the active note, and the hit line pulse
/// is suppressed.
struct FallingNotesView: View {
    // MARK: - Input Properties

    /// All note events for the current song, sorted by timestamp.
    let noteEvents: [NoteEvent]

    /// Wall-clock date representing time=0 of the song, set by the ViewModel
    /// on play/resume. When `nil` (paused/stopped), the last-computed time is frozen.
    /// `FallingNotesView` computes `currentTime` itself from this date inside
    /// `TimelineView`, so the ViewModel never needs to write a 20 Hz tick to
    /// drive the animation — eliminating the main actor pressure that caused
    /// MIDI scoring lag.
    let playbackStartDate: Date?

    /// Tempo scale factor (1.0 = original speed). Applied to currentTime computation.
    let tempoScale: Double

    /// Index of the note currently under the hit line, if any.
    let currentNoteIndex: Int?

    /// Per-note scoring states keyed by NoteEvent ID.
    let noteStates: [UUID: FallingNotesLayoutEngine.NoteState]

    /// Controls which label appears inside each note (Sargam, Western, etc.).
    let notationMode: NotationDisplayMode

    /// Horizontal positions of piano keys for note alignment.
    let keyPositions: [KeyPosition]

    /// AUD-027: Pre-built O(1) map from MIDI note → center-X.
    /// Computed once per `keyPositions` change instead of O(n) per note per frame.
    private var keyPositionMap: [UInt8: CGFloat] {
        FallingNotesLayoutEngine.buildKeyPositionMap(keyPositions)
    }

    /// Number of seconds of music visible in the viewport. Default is 4 seconds.
    var visibleDuration: TimeInterval = 4.0

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    /// Width of each falling note rectangle in points.
    private let noteWidth: CGFloat = 48

    /// Corner radius of note rectangles.
    private let noteCornerRadius: CGFloat = 6

    /// Height of the hit line indicator.
    private let hitLineHeight: CGFloat = 3

    /// Fractional Y position of the hit line within the viewport (0 = top, 1 = bottom).
    ///
    /// 0.85 places the hit line 85% down from the top, leaving 15% below
    /// for the piano keyboard transition zone. Notes fall toward this line.
    private let hitLineFraction: CGFloat = 0.85

    /// Minimum font size for note labels.
    private let labelFontSize: CGFloat = 13

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let viewportHeight = geometry.size.height
            let paused = playbackStartDate == nil

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
                // Compute currentTime directly from the timeline date so the
                // ViewModel never needs to write a periodic tick on @MainActor.
                let currentTime: TimeInterval = {
                    guard let startDate = playbackStartDate else {
                        // Paused — compute frozen time from last known state
                        if let index = currentNoteIndex, index < noteEvents.count {
                            return noteEvents[index].timestamp
                        }
                        return 0
                    }
                    return context.date.timeIntervalSince(startDate) / tempoScale
                }()

                Canvas { ctx, size in
                    drawHitLine(context: &ctx, size: size)
                    drawNotes(context: &ctx, size: size,
                              viewportHeight: viewportHeight,
                              currentTime: currentTime)
                }
                .accessibilityLabel(Text("Falling notes display"))
                .accessibilityHint(Text("Notes fall toward the piano keyboard. Play each note as it reaches the line."))
            }
        }
    }

    // MARK: - Drawing Methods

    /// Draw the horizontal hit line at `hitLineFraction` of the viewport height.
    private func drawHitLine(context: inout GraphicsContext, size: CGSize) {
        let hitLineY = size.height * hitLineFraction
        let hitLineRect = CGRect(
            x: 0,
            y: hitLineY - hitLineHeight / 2,
            width: size.width,
            height: hitLineHeight
        )
        context.fill(
            Path(hitLineRect),
            with: .color(.white.opacity(0.85))
        )
    }

    /// Draw all visible notes as rounded rectangles with labels.
    private func drawNotes(
        context: inout GraphicsContext,
        size: CGSize,
        viewportHeight: CGFloat,
        currentTime: TimeInterval
    ) {
        // Use hitLineY as the effective viewport height so notes fall toward
        // the hit line at 85% rather than the absolute bottom edge.
        let hitLineY = size.height * hitLineFraction
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: hitLineY,
            visibleDuration: visibleDuration
        )

        for event in noteEvents {
            let y = FallingNotesLayoutEngine.noteY(
                noteTimestamp: event.timestamp,
                currentTime: currentTime,
                pixelsPerSecond: pps,
                viewportHeight: hitLineY
            )
            let height = FallingNotesLayoutEngine.noteHeight(
                duration: event.duration,
                pixelsPerSecond: pps
            )

            // Viewport culling — skip off-screen notes (use full viewportHeight so
            // notes above the hit line but below the canvas bottom are still culled).
            guard FallingNotesLayoutEngine.isNoteVisible(
                noteY: y,
                noteHeight: height,
                viewportHeight: viewportHeight
            ) else {
                continue
            }

            // Horizontal alignment with the piano key.
            // Pass size.width so the fallback geometry uses the actual canvas width
            // on first render, before keyPositions is populated via preference.
            guard let centerX = FallingNotesLayoutEngine.noteX(
                midiNote: event.midiNote,
                keyPositionMap: keyPositionMap,
                viewWidth: size.width
            ) else {
                continue
            }

            let state = noteStates[event.id] ?? .upcoming
            let color = FallingNotesLayoutEngine.noteColor(state: state, swarName: event.swarName)

            // Note rectangle — y is the TOP edge of the note.
            let noteRect = CGRect(
                x: centerX - noteWidth / 2,
                y: y - height,
                width: noteWidth,
                height: height
            )
            let roundedPath = Path(
                roundedRect: noteRect,
                cornerRadius: noteCornerRadius
            )

            context.fill(roundedPath, with: .color(color))

            // Active note highlight ring (replaces blur glow — blur requires a
            // separate GPU render pass per note per frame, ~15ms at 200 BPM).
            if state == .active && !reduceMotion {
                context.stroke(
                    roundedPath,
                    with: .color(color.opacity(0.85)),
                    lineWidth: 3
                )
            }

            // Note label.
            let label = FallingNotesLayoutEngine.noteLabel(
                swarName: event.swarName,
                westernName: event.westernName,
                mode: notationMode
            )
            drawLabel(
                label,
                in: noteRect,
                context: &context,
                state: state
            )
        }
    }

    /// Draw a text label centered within a note rectangle.
    private func drawLabel(
        _ text: String,
        in rect: CGRect,
        context: inout GraphicsContext,
        state: FallingNotesLayoutEngine.NoteState
    ) {
        // Skip label if the note is too small to display text legibly.
        guard rect.height >= 20 else { return }

        let fontSize = min(labelFontSize, rect.height * 0.5)
        let textColor: Color = (state == .active || state == .correct) ? .black : .white

        let resolvedText = context.resolve(
            Text(verbatim: text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
        )

        let textSize = resolvedText.measure(in: rect.size)
        let textOrigin = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )

        context.draw(resolvedText, at: textOrigin, anchor: .topLeading)
    }
}

// MARK: - Preview

/// Helper that builds demo data for the falling notes preview.
private enum FallingNotesPreviewData {
    static let swarNames = [
        "Sa", "Komal Re", "Re", "Komal Ga", "Ga", "Ma",
        "Tivra Ma", "Pa", "Komal Dha", "Dha", "Komal Ni", "Ni",
    ]
    static let westernNames = [
        "C4", "Db4", "D4", "Eb4", "E4", "F4",
        "F#4", "G4", "Ab4", "A4", "Bb4", "B4",
    ]

    static func makeEvents() -> [NoteEvent] {
        (0..<12).map { index in
            NoteEvent(
                id: UUID(),
                midiNote: UInt8(60 + index),
                swarName: swarNames[index],
                westernName: westernNames[index],
                octave: 4,
                timestamp: TimeInterval(index) * 0.5,
                duration: 0.45,
                velocity: 100
            )
        }
    }

    static func makeKeyPositions() -> [KeyPosition] {
        (0..<12).map { index in
            KeyPosition(midiNote: UInt8(60 + index), centerX: CGFloat(40 + index * 30))
        }
    }
}

#Preview("Falling Notes — Demo") {
    let events = FallingNotesPreviewData.makeEvents()
    let positions = FallingNotesPreviewData.makeKeyPositions()

    FallingNotesView(
        noteEvents: events,
        playbackStartDate: Date(timeIntervalSinceNow: -2.0),
        tempoScale: 1.0,
        currentNoteIndex: 4,
        noteStates: [events[4].id: .active, events[3].id: .correct, events[2].id: .correct],
        notationMode: .sargam,
        keyPositions: positions
    )
    .background(Color.black)
    .frame(height: 400)
}
