// SurVibe/Play/TimelineWaterfallView.swift
import SVAudio
import SVCore
import SwiftUI

/// Vertical-scrolling, time-axis "falling notes" visualization of a take.
///
/// Each `RecordedNote` is drawn as a rounded rectangle whose horizontal
/// position encodes pitch (one column per semitone in the
/// `[lowMidi, highMidi)` range) and whose vertical extent encodes the
/// note's duration. The rectangles scroll upward past a fixed playhead
/// at the vertical centre as `positionSec` advances — notes ahead of the
/// playhead live in the lower half, notes already played live in the
/// upper half.
///
/// `activeNotes` (the `Set<Int>` of MIDI notes currently sounding,
/// derived from the playback engine's `HighlightSink`) is rendered with
/// a brighter fill so the user gets visual confirmation of which notes
/// the playhead is crossing right now. This is the **visual sync** half
/// of the two-stream design: the audible stream is sample-accurate via
/// `AVAudioSequencer` on slot 2; the visual stream is frame-paced via
/// `CADisplayLink` and assembled here purely from SwiftUI state — never
/// from the audio thread.
///
/// Drawing uses a single `Canvas` pass per frame so even snapshots with
/// thousands of notes (the 5,000-note hard cap) render in a few hundred
/// microseconds without churning the SwiftUI diff tree.
struct TimelineWaterfallView: View {

    // MARK: - Inputs

    /// The frozen take being visualised.
    let snapshot: TakeSnapshot
    /// Playhead position in seconds (post-speed snapshot timeline).
    let positionSec: TimeInterval
    /// MIDI notes currently sounding, supplied by the playback engine's
    /// `HighlightSink`. Used to brighten the corresponding rectangles.
    let activeNotes: Set<Int>

    // MARK: - Layout constants

    /// Vertical pixels representing one second of timeline.
    private let pixelsPerSecond: CGFloat = 60
    /// Width of one semitone column in points.
    private let keyColumnWidth: CGFloat = 8
    /// Lowest MIDI note rendered (C1).
    private let lowMidi: Int = 24
    /// Highest MIDI note rendered (C7, exclusive).
    private let highMidi: Int = 96

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let playheadY = size.height / 2
                    for note in snapshot.notes {
                        let col = Int(note.midi) - lowMidi
                        guard col >= 0, col < (highMidi - lowMidi) else { continue }

                        let x = CGFloat(col) * keyColumnWidth
                        // Higher onset = lower y on screen until the playhead
                        // catches up. Notes already played slide above the
                        // playhead, future notes wait below it.
                        let yBottom = CGFloat(note.onTimeSec - positionSec) * pixelsPerSecond + playheadY
                        let h = max(2, CGFloat(note.offTimeSec - note.onTimeSec) * pixelsPerSecond)
                        let yTop = yBottom - h

                        // Cull rectangles that are fully outside the visible
                        // area — keeps Canvas time bounded for very long takes.
                        if yTop > size.height || yBottom < 0 { continue }

                        let rect = CGRect(
                            x: x,
                            y: yTop,
                            width: keyColumnWidth - 1,
                            height: h
                        )
                        let isActive = activeNotes.contains(Int(note.midi))
                            && note.onTimeSec <= positionSec
                            && positionSec < note.offTimeSec
                        let fill: Color = isActive
                            ? .accentColor
                            : Color.accentColor.opacity(0.55)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill))
                    }
                }
                .accessibilityHidden(true)

                // Fixed playhead bar at the vertical centre.
                Rectangle()
                    .fill(Color.red.opacity(0.6))
                    .frame(height: 2)
                    .offset(y: geo.size.height / 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waterfall timeline")
        .accessibilityValue(
            "\(snapshot.notes.count) notes; \(activeNotes.count) currently sounding"
        )
    }
}
