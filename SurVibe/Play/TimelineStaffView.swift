// SurVibe/Play/TimelineStaffView.swift
import SVAudio
import SVCore
import SwiftUI

/// Horizontally scrolling staff view of a `TakeSnapshot`.
///
/// Renders notes as bars over a Canvas with a viewport cull (±4 s of `positionSec`)
/// so the per-frame draw work stays bounded for long takes. Task 15 polishes
/// this with proper treble/bass split, staff lines, and clefs; for T14 the
/// Canvas-based viewport cull satisfies the perf requirement and gives the
/// Expanded Timeline Sheet a working Staff tab.
struct TimelineStaffView: View {
    let snapshot: TakeSnapshot
    let positionSec: TimeInterval

    /// Horizontal scale: 80 px ≈ 1 second of take time.
    private let pixelsPerSecond: CGFloat = 80
    /// Vertical scale: 4 px per MIDI semitone.
    private let pixelsPerSemitone: CGFloat = 4
    /// Fixed canvas height — covers the full MIDI range at `pixelsPerSemitone`.
    private let canvasHeight: CGFloat = 512

    var body: some View {
        ScrollView(.horizontal) {
            Canvas { ctx, size in
                // Viewport cull: only draw notes whose on-time is within
                // ±4 seconds of the playhead. Keeps draw work bounded for
                // long takes (5,000 notes hard cap × ~30 min = ~25 px each).
                let visibleRange = (positionSec - 4)...(positionSec + 4)
                for note in snapshot.notes where visibleRange.contains(note.onTimeSec) {
                    let x = CGFloat(note.onTimeSec) * pixelsPerSecond
                    let y = CGFloat(127 - Int(note.midi)) * pixelsPerSemitone
                    let w = CGFloat(note.offTimeSec - note.onTimeSec) * pixelsPerSecond
                    let rect = CGRect(x: x, y: y, width: max(2, w), height: 6)
                    ctx.fill(Path(rect), with: .color(.accentColor))
                }
                // Playhead.
                let px = CGFloat(positionSec) * pixelsPerSecond
                ctx.stroke(
                    Path { p in
                        p.move(to: .init(x: px, y: 0))
                        p.addLine(to: .init(x: px, y: size.height))
                    },
                    with: .color(.red),
                    lineWidth: 1
                )
            }
            .frame(
                width: max(800, CGFloat(snapshot.notes.last?.offTimeSec ?? 1) * pixelsPerSecond),
                height: canvasHeight
            )
            .accessibilityLabel("Take staff timeline")
            .accessibilityValue(
                "\(snapshot.notes.count) notes, position \(positionSec.formattedAsClock)"
            )
        }
    }
}
