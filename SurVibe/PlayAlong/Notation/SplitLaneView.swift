import SwiftUI

/// Vertical falling-notes renderer split at middle-C.
///
/// Used by Neon Rhythm (#2 Arcade mode). Each MIDI note slot is a lane;
/// lanes left of middle-C (MIDI 60) render LH notes with red glow, lanes
/// right render RH notes with blue glow. Bars drop at a constant speed.
///
/// ## Reduce Motion (T11', HIG)
/// When `accessibilityReduceMotion` is on, the clock fed into bar-position
/// computation is **quantised to whole beats**, so notes advance in discrete
/// steps rather than scrolling continuously. Apple HIG: "When Reduce Motion
/// is active, ensure your app responds by reducing automatic and repetitive
/// animations, including peripheral motion."
/// See [Apple HIG — Motion](https://developer.apple.com/design/human-interface-guidelines/motion).
///
/// ## Hand shape coding (T11', HIG)
/// Each falling bar carries a **notehead** at its bottom (hit-line) edge whose
/// shape encodes the performing hand independently of color:
///   - Right hand → circle.
///   - Left hand  → square.
///   - Chord (≥2 simultaneous notes) → filled diamond.
/// See [Apple HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color).
///
/// ## Latency contract
/// Colors arrive as `let` parameters. This view MUST NOT read
/// `@Environment(AppThemeManager.self)`. Canvas-based drawing avoids
/// per-frame SwiftUI re-renders.
struct SplitLaneView: View {
    let noteEvents: [NoteEvent]
    let currentTime: TimeInterval
    let rhColor: Color
    let lhColor: Color
    let chordColor: Color

    /// Tempo in BPM, used to quantise `currentTime` to whole-beat steps when
    /// Reduce Motion is enabled. Defaults to 120 to keep existing call sites
    /// compiling; `SongPlayAlongView` passes the song's actual tempo.
    var tempoBPM: Double = 120

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// Effective playback time used to compute bar positions.
    ///
    /// When Reduce Motion is on, this is rounded down to the most recent
    /// whole-beat boundary so falling bars advance in discrete steps.
    private var effectiveTime: TimeInterval {
        guard reduceMotion else { return currentTime }
        let secondsPerBeat = 60.0 / max(1.0, tempoBPM)
        return floor(currentTime / secondsPerBeat) * secondsPerBeat
    }

    /// Seconds of lookahead visible above the hit line.
    private let windowSeconds: TimeInterval = 3.0

    /// Hit line is at the bottom of the drawing area.
    private let hitLineFraction: CGFloat = 0.92

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                drawSplit(ctx: ctx, size: size)
                drawLanes(ctx: ctx, size: size)
                drawBars(ctx: ctx, size: size)
                drawHitLine(ctx: ctx, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Split-lane falling notes: left hand on the left, right hand on the right")
    }

    // MARK: - Layout constants

    private var leftSideLanes: Int { 24 }  // MIDI 36..59 → LH
    private var rightSideLanes: Int { 24 }  // MIDI 60..83 → RH
    private var totalLanes: Int { leftSideLanes + rightSideLanes }

    private func laneWidth(for size: CGSize) -> CGFloat {
        size.width / CGFloat(totalLanes)
    }

    private func midiToLaneX(_ midi: Int, size: CGSize) -> CGFloat {
        let clamped = max(36, min(83, midi))
        let index = clamped - 36
        return CGFloat(index) * laneWidth(for: size)
    }

    // MARK: - Drawing

    private func drawSplit(ctx: GraphicsContext, size: CGSize) {
        // Dashed vertical line at middle-C (MIDI 60, lane index 24)
        let splitX = CGFloat(leftSideLanes) * laneWidth(for: size)
        var path = Path()
        path.move(to: CGPoint(x: splitX, y: 0))
        path.addLine(to: CGPoint(x: splitX, y: size.height))
        ctx.stroke(
            path,
            with: .color(.white.opacity(0.15)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    private func drawLanes(ctx: GraphicsContext, size: CGSize) {
        let lw = laneWidth(for: size)
        for i in 1..<totalLanes {
            var path = Path()
            let x = CGFloat(i) * lw
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 0.5)
        }
    }

    private func drawBars(ctx: GraphicsContext, size: CGSize) {
        let hitLineY = size.height * hitLineFraction
        let pixelsPerSecond = hitLineY / CGFloat(windowSeconds)
        let lw = laneWidth(for: size)

        // Chord group detection — ≥2 notes sharing timestamp (within 10ms).
        let chordTimestamps = chordTimestamps()

        let nowTime = effectiveTime
        for event in noteEvents {
            let timeUntilHit = event.timestamp - nowTime
            if timeUntilHit > windowSeconds || timeUntilHit < -event.duration {
                continue  // Off-screen
            }

            let centerY = hitLineY - CGFloat(timeUntilHit) * pixelsPerSecond
            let barHeight = max(8, CGFloat(event.duration) * pixelsPerSecond)
            let topY = centerY - barHeight / 2
            let x = midiToLaneX(Int(event.midiNote), size: size)

            let isChordNote = chordTimestamps.contains { abs($0 - event.timestamp) < 0.01 }
            let color: Color = {
                if isChordNote { return chordColor }
                return event.hand == .right ? rhColor : lhColor
            }()

            let rect = CGRect(x: x + 2, y: topY, width: lw - 4, height: barHeight)
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(color)
            )
            // Glow outline
            ctx.stroke(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(color.opacity(0.4)),
                lineWidth: 2
            )

            // Hand-shape coded notehead at the bar's bottom (hit-line) edge.
            // RH=circle, LH=square, chord=filled diamond. See HIG comment above.
            drawNotehead(
                ctx: ctx,
                centerX: rect.midX,
                centerY: min(rect.maxY, hitLineY),
                hand: event.hand,
                isChord: isChordNote,
                color: color
            )
        }
    }

    /// Draw a notehead whose **shape** encodes the performing hand
    /// independently of color (HIG: convey information with more than color alone).
    private func drawNotehead(
        ctx: GraphicsContext,
        centerX: CGFloat,
        centerY: CGFloat,
        hand: Hand,
        isChord: Bool,
        color: Color
    ) {
        let radius: CGFloat = 6
        let path: Path = {
            if isChord {
                var p = Path()
                p.move(to: CGPoint(x: centerX, y: centerY - radius))
                p.addLine(to: CGPoint(x: centerX + radius, y: centerY))
                p.addLine(to: CGPoint(x: centerX, y: centerY + radius))
                p.addLine(to: CGPoint(x: centerX - radius, y: centerY))
                p.closeSubpath()
                return p
            }
            switch hand {
            case .right:
                return Path(ellipseIn: CGRect(
                    x: centerX - radius, y: centerY - radius,
                    width: radius * 2, height: radius * 2))
            case .left:
                return Path(CGRect(
                    x: centerX - radius, y: centerY - radius,
                    width: radius * 2, height: radius * 2))
            }
        }()
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1)
    }

    private func drawHitLine(ctx: GraphicsContext, size: CGSize) {
        let hitLineY = size.height * hitLineFraction
        var path = Path()
        path.move(to: CGPoint(x: 0, y: hitLineY))
        path.addLine(to: CGPoint(x: size.width, y: hitLineY))
        ctx.stroke(path, with: .color(.white), lineWidth: 1.5)
    }

    // MARK: - Chord detection

    /// Timestamps (within 10ms buckets) that have ≥2 concurrent notes.
    private func chordTimestamps() -> Set<Double> {
        var buckets: [Int: Int] = [:]
        for event in noteEvents {
            let bucket = Int((event.timestamp * 100).rounded())  // 10ms resolution
            buckets[bucket, default: 0] += 1
        }
        return Set(
            buckets.filter { $0.value >= 2 }.keys.map { Double($0) / 100 }
        )
    }
}

#Preview("Empty") {
    SplitLaneView(
        noteEvents: [],
        currentTime: 0,
        rhColor: Color(red: 0.00, green: 0.48, blue: 1.00),
        lhColor: Color(red: 1.00, green: 0.23, blue: 0.19),
        chordColor: Color(red: 0.61, green: 0.15, blue: 0.69)
    )
    .frame(width: 800, height: 500)
    .background(Color.black)
}
