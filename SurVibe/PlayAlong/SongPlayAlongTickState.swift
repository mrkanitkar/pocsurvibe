// SurVibe/PlayAlong/Lean/SongPlayAlongTickState.swift
import Foundation
import SVAudio

/// Display-link tick state for Songs Play Along.
///
/// Isolated `@Observable` so per-frame writes invalidate only the leaf
/// subviews that read from it — never `SongPlayAlongView.body`. Mirrors
/// Play tab's `PlayTabHighlightState` (the proven pattern in this codebase).
///
/// Owned by `SongPlayAlongViewModel`. Written from one place: the
/// `TakePlaybackEngine.onVisualTick` callback. Read from three subviews:
/// the sheet, the keyboard, and the pitch feedback bar.
@Observable
@MainActor
final class SongPlayAlongTickState {

    /// Index into `viewModel.noteEvents` of the note the cursor sits on.
    /// Driven by the visual-tick handler.
    var currentNoteIndex: Int?

    /// Wall-clock playback position in seconds. Smooth, monotonic when
    /// playing; paused-aware.
    var currentTime: TimeInterval = 0

    /// MIDI note numbers the sequencer is currently sounding. Read by the
    /// keyboard view; unioned with user-press notes there.
    var activeMidiNotes: Set<Int> = []

    /// Keys the user is currently touching on the on-screen piano.
    /// Read by the keyboard view; unioned with `activeMidiNotes`
    /// for highlight.
    var userPressedNotes: Set<Int> = []

    /// Most recent mic-pitch result above amplitude+confidence thresholds.
    /// `nil` when the mic is silent. Read by the pitch feedback bar.
    /// Publish rate throttled to ~10 Hz by the writer.
    var detectedPitch: PitchResult?

    /// Reset every field to its empty state. Called on song teardown.
    func reset() {
        currentNoteIndex = nil
        currentTime = 0
        activeMidiNotes = []
        userPressedNotes = []
        detectedPitch = nil
    }
}
