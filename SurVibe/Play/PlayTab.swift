// SurVibe/Play/PlayTab.swift
import SVAudio
import SVCore
import SwiftUI

/// Top-level Play tab view. Free-play surface with instrument picker,
/// live-highlight grand staff, recording strip, and on-screen + MIDI keyboard.
struct PlayTab: View {
    @State
    private var viewModel: PlayTabViewModel = {
        let coord = MIDINoteHighlightCoordinator()
        // Engine and MIDI manager come from singletons; cast to the protocol.
        let engine =
            AudioEngineManager.shared.multiChannel as (any PlayTabAudioEngine)?
            ?? PlaceholderAudioEngine()  // engine missing if startForPlayback hasn't run yet
        let midi = MIDIInputManager.shared as any MIDIInputProviding
        return PlayTabViewModel(engine: engine, midiInput: midi, highlightCoordinator: coord)
    }()

    @State
    private var isPickerPresented = false
    @State
    private var connectedDeviceNames: [String] = []
    /// Isolated observable holding the display-link-driven highlight set.
    ///
    /// PlayTab.body never reads `highlightState.activeMidiNotes`, so SwiftUI
    /// does NOT re-render PlayTab when the MIDI thread updates the highlight
    /// set. Only `LiveHighlightStaffView` and `LargePianoView` (which read
    /// the property) re-render — matching PlayAlong's scoping path.
    @State
    private var highlightState = PlayTabHighlightState()
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            PlayTabToolbar(
                viewModel: viewModel,
                connectedDeviceNames: connectedDeviceNames,
                onTapInstrument: { isPickerPresented = true }
            )
            if let banner = viewModel.lastError {
                Text(banner)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
            }
            LiveHighlightStaffView(
                highlightState: highlightState,
                saPitch: viewModel.saPitch,
                notationMode: viewModel.notationMode,
                recordedNotes: viewModel.recordedNotes
            )
            .frame(maxHeight: .infinity)
            RecordingStripView(
                recordedNotes: viewModel.recordedNotes,
                saPitch: viewModel.saPitch,
                notationMode: viewModel.notationMode,
                onClear: { viewModel.clearStrip() }
            )
            LargePianoView(
                highlightState: highlightState,
                onNoteOn: { midi in
                    viewModel.handleNoteOn(UInt8(midi), velocity: 100, source: .touch)
                },
                onNoteOff: { midi in
                    viewModel.handleNoteOff(UInt8(midi), source: .touch)
                }
            )
            .frame(height: 280)
        }
        .task {
            do {
                try AudioEngineManager.shared.startForPlayback()
                if let realEngine = AudioEngineManager.shared.multiChannel
                    as (any PlayTabAudioEngine)?
                {
                    viewModel.attachEngine(realEngine)
                }
            } catch {
                // VM's onAppear will surface engine failures via lastError.
            }
            // CoreMIDI client/port creation. Idempotent — safe if already started.
            MIDIInputManager.shared.start()
            viewModel.onAppear()
            // Drive the visual highlight (staff + on-screen keyboard) from
            // the display-link-driven coordinator so MIDI→highlight latency
            // is bounded by display refresh (~8–16 ms) instead of an
            // unbounded `Task { @MainActor }` hop in the bookkeeping path.
            //
            // Capture `highlightState` strongly: only the staff + keyboard
            // observe `activeMidiNotes`, so PlayTab.body is NOT invalidated
            // by writes here. This mirrors PlayAlong's HighlightState path.
            //
            // VM bookkeeping (`activeMidiNotes`, `recordedNotes`) is unaffected.
            viewModel.installHighlightObserver { [hs = highlightState] notes in
                let timestampMicros = DispatchTime.now().uptimeNanoseconds / 1_000
                print("[PlayTab][displayLink] notes=\(notes.count) ts=\(timestampMicros)")
                hs.activeMidiNotes = notes
            }
            // `MIDIInputManager.refreshSources()` yields the new connection
            // state on the connection stream BEFORE its `Task { @MainActor }`
            // setter that writes `connectedDeviceName` runs. Without yielding
            // first we would read the previous (often nil) value and the
            // toolbar badge would stay empty after a hot-plug. One yield is
            // enough to drain the queued setter on the main actor.
            await Task.yield()
            refreshDeviceList()
            // React to hot-plug/unplug. `connectionStateStream` yields `true`
            // when a source connects and `false` when all sources disconnect;
            // either transition warrants refreshing the toolbar badge name.
            // The `for await` is the LAST statement in `.task` — anything
            // after it would be unreachable. SwiftUI auto-cancels this task
            // (and the stream's continuation) on view disappear.
            for await _ in MIDIInputManager.shared.connectionStateStream {
                // Same race as above: the stream fires on the CoreMIDI thread
                // synchronously with `connectionBox.yield(...)`, but the
                // `connectedDeviceName` setter is queued via
                // `Task { @MainActor }`. Yield once to let it drain.
                await Task.yield()
                refreshDeviceList()
            }
        }
        .onDisappear {
            // Don't stop the shared MIDIInputManager — it's owned by the
            // process and other features (Play-Along) may still need it.
            // `viewModel.onDisappear()` clears the onNoteEvent closure.
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background: viewModel.allNotesOff()
            case .active: viewModel.onAppear()
            // .inactive (control-center pull, banner) must NOT kill held notes.
            case .inactive: break
            @unknown default: break
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            InstrumentPickerSheet(currentProgram: viewModel.currentInstrument) { program in
                viewModel.setInstrument(program)
            }
        }
    }

    private func refreshDeviceList() {
        connectedDeviceNames = [MIDIInputManager.shared.connectedDeviceName].compactMap { $0 }
    }
}

/// No-op engine placeholder used only during the brief window before
/// AudioEngineManager.startForPlayback() succeeds.
private final class PlaceholderAudioEngine: PlayTabAudioEngine, @unchecked Sendable {
    @MainActor
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws {}
    nonisolated func playTouchNote(_ midiNote: UInt8, velocity: UInt8) {}
    nonisolated func stopTouchNote(_ midiNote: UInt8) {}
    nonisolated func stopAllTouchNotes() {}
}

#Preview {
    PlayTab()
}
