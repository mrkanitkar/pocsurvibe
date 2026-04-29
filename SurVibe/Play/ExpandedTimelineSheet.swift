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
/// Wave 4 / Task 15 fills in `TimelineWaterfallView` and wires the
/// `MIDINoteHighlightCoordinator` as the visual sink.
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

            switch tab {
            case .staff:
                TimelineStaffView(snapshot: snapshot, positionSec: positionSec)
            case .waterfall:
                // Filled in by Task 15 (TimelineWaterfallView + visual sync).
                ContentUnavailableView(
                    "Waterfall view coming soon",
                    systemImage: "rectangle.stack.fill",
                    description: Text("Wave 4 / Task 15 lands the falling-note view.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notes:
                Text("Notes editing in Task 16")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            transportBar
        }
        .presentationDetents([.large])
        .onAppear { setUpPlaybackEngine() }
        .onDisappear { playbackEngine?.stop() }
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
        guard let multiChannel = AudioEngineManager.shared.multiChannel else { return }
        let engine = TakePlaybackEngine(
            multiChannel: multiChannel,
            highlightSink: nil,                     // wired in Task 15
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

    private func reschedule(speed: Double, hand: HandFilter) async {
        await playbackEngine?.schedule(
            snapshot: snapshot,
            speed: speed,
            handFilter: hand,
            saMidi: snapshot.saPitchMidi
        )
    }
}
