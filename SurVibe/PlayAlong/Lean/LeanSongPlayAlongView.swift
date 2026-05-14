// SurVibe/PlayAlong/Lean/SongPlayAlongView.swift
import SVAudio
import SVCore
import SVLearning
import SwiftData
import SwiftUI

/// Lean play-along view for a single song. Replaces the 800-line
/// `SongPlayAlongView` + four extension files with one composed VStack.
///
/// Layout mirrors the user's screenshot:
///   1. Toolbar — back, play/pause, restart, time, tempo
///   2. Sheet — `ScrollingSheetView` (grand staff)
///   3. Score row — accuracy %, hits / total
///   4. Pitch feedback — Detected / Cents / Confidence
///   5. Keyboard — `InteractivePianoView` with RH/LH coloring
///
/// Every per-frame observable (`currentNoteIndex`, `activeMidiNotes`,
/// `detectedPitch`) is read inside a leaf subview that takes the
/// `tickState` as a `let` parameter. The body itself never reads
/// `tickState.*` — so display-link writes don't invalidate the body.
@MainActor
struct LeanSongPlayAlongView: View {

    let song: Song

    @State private var viewModel = SongPlayAlongViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SheetSection(
                song: song,
                noteEvents: viewModel.noteEvents,
                tickState: viewModel.tickState,
                isPlaying: viewModel.playbackState == .playing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            scoreSection
            PitchFeedbackSection(tickState: viewModel.tickState)
            KeyboardSection(
                tickState: viewModel.tickState,
                onNoteOn: { viewModel.handleKeyboardNoteOn($0) },
                onNoteOff: { viewModel.handleKeyboardNoteOff($0) }
            )
            .frame(height: 280)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.modelContext = modelContext
            await viewModel.loadSong(song)
            viewModel.startPitchDetection()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .overlay {
            if viewModel.playbackState == .stopped, let scoring = viewModel.scoring {
                SongPlayAlongResults(
                    songTitle: song.title,
                    accuracyPercent: scoring.accuracyPercent,
                    notesHit: scoring.notesHit,
                    totalNotes: scoring.totalNotes,
                    onReplay: { Task { await viewModel.restart() } },
                    onDone: { dismiss() }
                )
            }
        }
        .accessibilityLabel("Play along with \(song.title)")
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: handlePlayPause) {
                Image(systemName: playPauseIcon).font(.title2)
            }
            .accessibilityLabel(viewModel.playbackState == .playing ? "Pause" : "Play")

            Button(action: { Task { await viewModel.restart() } }) {
                Image(systemName: "arrow.counterclockwise").font(.title3)
            }
            .accessibilityLabel("Restart")

            Spacer()

            TimeDisplay(
                duration: viewModel.duration,
                tickState: viewModel.tickState
            )

            Spacer()

            tempoControl
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var tempoControl: some View {
        HStack(spacing: 8) {
            Text("\(Int(viewModel.tempoScale * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { viewModel.tempoScale },
                    set: { viewModel.tempoScale = $0 }
                ),
                in: 0.5...1.5,
                step: 0.05
            )
            .frame(width: 140)
            .accessibilityLabel("Tempo")
        }
    }

    private var playPauseIcon: String {
        switch viewModel.playbackState {
        case .playing: return "pause.fill"
        case .paused, .idle, .stopped: return "play.fill"
        case .loading: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func handlePlayPause() {
        switch viewModel.playbackState {
        case .idle, .stopped:
            Task { await viewModel.play() }
        case .playing:
            viewModel.pause()
        case .paused:
            viewModel.resume()
        case .loading, .error:
            break
        }
    }

    // MARK: - Score

    @ViewBuilder
    private var scoreSection: some View {
        if let scoring = viewModel.scoring {
            HStack(spacing: 16) {
                Text("\(scoring.accuracyPercent)%")
                    .font(.title3.monospacedDigit().bold())
                    .accessibilityLabel("Accuracy \(scoring.accuracyPercent) percent")
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text("\(scoring.notesHit) / \(scoring.totalNotes)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(scoring.notesHit) of \(scoring.totalNotes) notes hit")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Leaf subviews (each owns its tickState read)

/// Leaf reader of `tickState.currentTime`. Shown in the toolbar so the
/// per-tick clock advance invalidates only this small Text, not the
/// entire toolbar.
@MainActor
struct TimeDisplay: View {
    let duration: TimeInterval
    let tickState: SongPlayAlongTickState

    var body: some View {
        Text("\(timeString(tickState.currentTime)) / \(timeString(duration))")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(
                "Time \(timeString(tickState.currentTime)) of \(timeString(duration))"
            )
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Leaf reader of `tickState.currentTime`. Renders the **Play tab's
/// `TimelineGrandStaffView`** — the same grand-staff component the user
/// already knows from Play. Treble + bass clefs share a single time
/// axis, notes line up vertically across hands, and a vivid vertical
/// playhead bar moves through them. Auto-scrolls to keep the playhead
/// centered while playing.
///
/// Converts `[NoteEvent]` → `[RecordedNote]` so the existing renderer
/// works unchanged. Hand assignment in `TimelineGrandStaffView` uses
/// `midi < 60 ? bass : treble`, which matches the song's authored
/// LH/RH split for piano repertoire.
@MainActor
struct SheetSection: View {
    let song: Song
    let noteEvents: [NoteEvent]
    let tickState: SongPlayAlongTickState
    let isPlaying: Bool

    var body: some View {
        TimelineGrandStaffView(
            notes: recordedNotes,
            positionSec: tickState.currentTime,
            isPlaying: isPlaying
        )
    }

    private var recordedNotes: [RecordedNote] {
        noteEvents.map { ev in
            RecordedNote(
                id: ev.id,
                midi: ev.midiNote,
                velocity: ev.velocity,
                onTimeSec: ev.timestamp,
                offTimeSec: ev.timestamp + ev.duration
            )
        }
    }
}

/// Leaf reader of `tickState.detectedPitch`. Shows the Detected / Cents /
/// Confidence row from the user's screenshot. Renders an empty placeholder
/// when no pitch is detected so the layout doesn't jump.
@MainActor
struct PitchFeedbackSection: View {
    let tickState: SongPlayAlongTickState

    var body: some View {
        if let pitch = tickState.detectedPitch {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detected").font(.caption2).foregroundStyle(.secondary)
                    Text(pitch.noteName).font(.headline.bold())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cents").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%+.0f", pitch.centsOffset))
                        .font(.callout.monospacedDigit())
                }
                PitchProximityMeter(
                    centsOffset: pitch.centsOffset,
                    trackColor: Color(.systemGray4),
                    centerLineColor: .green
                )
                .frame(width: 24, height: 40)
                .accessibilityHidden(true)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Confidence").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(pitch.confidence * 100))%")
                        .font(.callout.monospacedDigit())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Detected \(pitch.noteName), \(Int(pitch.centsOffset)) cents, "
                    + "confidence \(Int(pitch.confidence * 100)) percent"
            )
        } else {
            // Maintain layout height when no pitch is detected.
            Color.clear.frame(height: 40)
        }
    }
}

/// Leaf reader of `tickState.activeMidiNotes` + `userPressedNotes`. The
/// only subview that re-renders on display-link writes to the
/// sequenced-notes set — `SongPlayAlongView.body` never sees it.
@MainActor
struct KeyboardSection: View {
    let tickState: SongPlayAlongTickState
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        InteractivePianoView(
            activeMidiNotes: tickState.activeMidiNotes.union(tickState.userPressedNotes),
            highlightState: nil,
            activeCentsOffset: tickState.detectedPitch?.centsOffset ?? 0,
            expectedMidiNote: nil,
            onNoteOn: onNoteOn,
            onNoteOff: onNoteOff,
            notationMode: .dual,
            manageSoundFont: false
        )
    }
}
