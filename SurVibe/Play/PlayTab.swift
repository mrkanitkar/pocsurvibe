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
                activeMidiNotes: viewModel.activeMidiNotes,
                saPitch: viewModel.saPitch,
                notationMode: viewModel.notationMode
            )
            .frame(maxHeight: .infinity)
            RecordingStripView(
                recordedNotes: viewModel.recordedNotes,
                saPitch: viewModel.saPitch,
                notationMode: viewModel.notationMode,
                onClear: { viewModel.clearStrip() }
            )
            InteractivePianoView(
                activeMidiNotes: Set(viewModel.activeMidiNotes.map(Int.init)),
                activeCentsOffset: 0.0,
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
            refreshDeviceList()
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
private final class PlaceholderAudioEngine: PlayTabAudioEngine {
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws {}
    func playTouchNote(_ midiNote: UInt8, velocity: UInt8) {}
    func stopTouchNote(_ midiNote: UInt8) {}
    func stopAllTouchNotes() {}
}

#Preview {
    PlayTab()
}
