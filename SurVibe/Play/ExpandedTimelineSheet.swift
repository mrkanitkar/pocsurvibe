// SurVibe/Play/ExpandedTimelineSheet.swift
import SVAudio
import SVCore
import SwiftUI

/// Full-screen sheet that owns the Staff / Waterfall / Notes tabs plus the
/// transport bar for take playback.
///
/// Constructed lazily by `PlayTab` when the user taps `⤢` on the bottom strip.
/// Reads a frozen `TakeSnapshot` (passed in by the caller) so it never
/// re-renders on live `ScratchpadState` mutations — see spec §5.4.2 + §5.2.2.
///
/// Tab + transport state is owned here (not on the view model) because the
/// sheet is ephemeral; closing and reopening should not preserve seek/speed.
///
/// **Visual sync (Task 15).** The sheet owns a dedicated
/// `MIDINoteHighlightCoordinator` and hands it to `TakePlaybackEngine` as the
/// `HighlightSink`. The engine's `CADisplayLink` calls
/// `noteOn`/`noteOff` from the main thread; the coordinator's own display
/// link enforces the 80 ms minimum visual hold and publishes the active-set
/// via `onActiveNotesChanged`. The coordinator is sheet-scoped so highlight
/// state cannot leak back into the live PlayTab keyboard underneath the
/// sheet — the two streams (audible-via-AVAudioSequencer, visual-via-
/// HighlightSink) stay decoupled even though both are driven by the engine.
struct ExpandedTimelineSheet: View {
    /// Tabs presented inside the sheet. `notes` is filtered out for the live
    /// scratchpad case (`isTake == false`); annotations only make sense once
    /// the scratchpad has been materialised into a `RecordedTake`.
    enum Tab: String, CaseIterable, Identifiable {
        case staff = "Staff"
        case waterfall = "Waterfall"
        case notes = "Notes"
        var id: String { rawValue }
    }

    let snapshot: TakeSnapshot
    /// `true` when the sheet was opened against a saved take (Notes tab visible).
    /// `false` for the live scratchpad path used by Task 14.
    let isTake: Bool
    @Binding var presented: Bool

    @State private var tab: Tab = .staff
    @State private var playbackEngine: TakePlaybackEngine?
    @State private var positionSec: TimeInterval = 0
    @State private var speed: Double = 1.0
    @State private var hand: HandFilter = .both

    /// Sheet-scoped highlight coordinator. Acts as the `HighlightSink` for
    /// `TakePlaybackEngine` and republishes the active-note set into
    /// `activeHighlightedNotes` for `TimelineWaterfallView` to render.
    @State private var highlightCoordinator: MIDINoteHighlightCoordinator = .init()

    /// MIDI note numbers currently being highlighted by the engine's visual
    /// link, after the coordinator's minimum-hold has been applied. Driven
    /// by `highlightCoordinator.onActiveNotesChanged`.
    @State private var activeHighlightedNotes: Set<Int> = []

    private var maxPositionSec: TimeInterval {
        max(snapshot.notes.last?.offTimeSec ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $tab) {
                ForEach(Tab.allCases.filter { $0 != .notes || isTake }) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Frame-paced playhead: TimelineView re-evaluates the inner
            // closure every display frame, pulling `currentPositionSec`
            // off the (main-thread) sequencer. This drives both the staff
            // and waterfall views without any work on the audio thread.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { _ in
                tabContent
                    .onChange(of: shouldSampleNow) { _, _ in
                        if let engine = playbackEngine, engine.isPlaying {
                            positionSec = min(engine.currentPositionSec, maxPositionSec)
                        }
                    }
            }

            Spacer(minLength: 0)

            transportBar
        }
        .presentationDetents([.large])
        .onAppear { setUpPlaybackEngine() }
        .onDisappear { tearDownPlaybackEngine() }
    }

    /// Tracks `playbackEngine?.isPlaying` so the `TimelineView` can pause
    /// frame ticks when stopped (avoids burning a display frame for the
    /// no-op sample).
    private var isPlaying: Bool { playbackEngine?.isPlaying ?? false }

    /// Read-only wrapper used as a `.onChange` trigger inside the
    /// `TimelineView` closure — its value changes every frame while
    /// playing, which is what drives the position sample.
    private var shouldSampleNow: Date { Date() }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .staff:
            TimelineStaffView(snapshot: snapshot, positionSec: positionSec)
        case .waterfall:
            TimelineWaterfallView(
                snapshot: snapshot,
                positionSec: positionSec,
                activeNotes: activeHighlightedNotes
            )
        case .notes:
            Text("Notes editing in Task 16")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Transport bar

    @ViewBuilder
    private var transportBar: some View {
        HStack(spacing: 16) {
            Button {
                playbackEngine?.play()
            } label: {
                Image(systemName: "play.fill")
            }
            .accessibilityLabel("Play")

            Button {
                playbackEngine?.pause()
            } label: {
                Image(systemName: "pause.fill")
            }
            .accessibilityLabel("Pause")

            Button {
                positionSec = 0
                playbackEngine?.seek(to: 0)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityLabel("Restart")

            Slider(
                value: $positionSec,
                in: 0...maxPositionSec
            ) { editing in
                if !editing { playbackEngine?.seek(to: positionSec) }
            }
            .accessibilityLabel("Playhead")

            Picker("Speed", selection: $speed) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) {
                    Text("\($0, format: .number)×").tag($0)
                }
            }
            .onChange(of: speed) { _, newValue in
                Task { await reschedule(speed: newValue, hand: hand) }
            }

            Picker("Hands", selection: $hand) {
                Text("Both").tag(HandFilter.both)
                Text("Treble").tag(HandFilter.trebleOnly)
                Text("Bass").tag(HandFilter.bassOnly)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .onChange(of: hand) { _, newValue in
                Task { await reschedule(speed: speed, hand: newValue) }
            }
        }
        .padding()
    }

    // MARK: - Playback engine wiring

    private func setUpPlaybackEngine() {
        // Coordinator must be running before the engine starts firing
        // `noteOn` / `noteOff` so the display link sees the events.
        highlightCoordinator.onActiveNotesChanged = { newSet in
            activeHighlightedNotes = newSet
        }
        highlightCoordinator.start()

        guard let multiChannel = AudioEngineManager.shared.multiChannel else { return }
        let engine = TakePlaybackEngine(
            multiChannel: multiChannel,
            highlightSink: highlightCoordinator,
            engine: AudioEngineManager.shared.engine
        )
        playbackEngine = engine
        Task {
            await engine.schedule(
                snapshot: snapshot,
                speed: speed,
                handFilter: hand,
                saMidi: snapshot.saPitchMidi
            )
        }
    }

    private func tearDownPlaybackEngine() {
        playbackEngine?.stop()
        highlightCoordinator.onActiveNotesChanged = nil
        highlightCoordinator.stop()
        activeHighlightedNotes = []
    }

    private func reschedule(speed: Double, hand: HandFilter) async {
        await playbackEngine?.schedule(
            snapshot: snapshot,
            speed: speed,
            handFilter: hand,
            saMidi: snapshot.saPitchMidi
        )
    }
}
