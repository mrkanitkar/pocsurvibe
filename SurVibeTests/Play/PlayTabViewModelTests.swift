import Foundation
import SVAudio
import SVCore
import Testing

@testable import SurVibe

@MainActor
struct PlayTabViewModelTests {
    private func makeVM(
        engine: MockPlayTabAudioEngine? = nil,
        midi: MockMIDIInputProviding? = nil
    ) -> (PlayTabViewModel, MockPlayTabAudioEngine, MockMIDIInputProviding) {
        let engine = engine ?? MockPlayTabAudioEngine()
        let midi = midi ?? MockMIDIInputProviding()
        // Clear UserDefaults to avoid bleed between tests.
        UserDefaults.standard.removeObject(forKey: "playTab.lastInstrument")
        UserDefaults.standard.removeObject(forKey: "playTab.saPitch")
        let coord = MIDINoteHighlightCoordinator()
        let vm = PlayTabViewModel(engine: engine, midiInput: midi, highlightCoordinator: coord)
        return (vm, engine, midi)
    }

    // MARK: - Defaults

    @Test
    func defaultInstrumentIsAcousticGrand() {
        let (vm, _, _) = makeVM()
        #expect(vm.currentInstrument == 0)
    }

    @Test
    func defaultSaIsMiddleC() {
        let (vm, _, _) = makeVM()
        #expect(vm.saPitch == 60)
    }

    @Test
    func defaultNotationModeIsBoth() {
        let (vm, _, _) = makeVM()
        #expect(vm.notationMode == .both)
    }

    // MARK: - setInstrument

    @Test
    func setInstrumentLoadsProgramOnSamplerZero() {
        let (vm, engine, _) = makeVM()
        vm.setInstrument(24)
        #expect(engine.loadProgramCalls.count == 1)
        #expect(engine.loadProgramCalls[0].index == 0)
        #expect(engine.loadProgramCalls[0].program == 24)
        #expect(engine.loadProgramCalls[0].isPercussion == false)
        #expect(vm.currentInstrument == 24)
    }

    @Test
    func setInstrumentStopsRingingNotes() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(60, velocity: 100, source: .midi)
        engine.stopAllTouchNotesCallCount = 0
        vm.setInstrument(24)
        #expect(engine.stopAllTouchNotesCallCount == 1)
        #expect(vm.activeMidiNotes.isEmpty)
    }

    @Test
    func setInstrumentRollsBackOnLoadFailure() {
        let (vm, engine, _) = makeVM()
        vm.setInstrument(0)  // baseline; succeeds
        engine.loadProgramShouldThrow = MockPlayTabAudioEngine.MockError.loadFailed
        vm.setInstrument(40)
        #expect(vm.currentInstrument == 0)  // rolled back
        #expect(vm.lastError != nil)
    }

    // MARK: - Touch path: VM observes only

    @Test
    func touchHandleNoteOnDoesNotPlayAudio() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 100, source: .touch)
        #expect(
            engine.playTouchNoteCalls.isEmpty,
            "Touch already plays via InteractivePianoView; VM must not duplicate"
        )
        #expect(vm.activeMidiNotes == [67])
        // Note-on opens a pending entry in the scratchpad; closed `notes`
        // remain empty until a note-off arrives.
        #expect(vm.scratchpad.notes.isEmpty)
        #expect(vm.scratchpad.hasContent)
    }

    @Test
    func touchHandleNoteOffDoesNotStopAudio() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 100, source: .touch)
        vm.handleNoteOff(67, source: .touch)
        #expect(engine.stopTouchNoteCalls.isEmpty)
        #expect(vm.activeMidiNotes.isEmpty)
        // Note-off materialises the note into the scratchpad.
        #expect(vm.scratchpad.notes.count == 1)
        #expect(vm.scratchpad.notes[0].midi == 67)
    }

    // MARK: - MIDI path: VM never plays through the iPad sampler

    @Test
    func midiHandleNoteOnNeverPlaysThroughIPadSampler() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 80, source: .midi)
        #expect(
            engine.playTouchNoteCalls.isEmpty,
            "MIDI input must never echo through the iPad sampler — the external keyboard makes sound"
        )
        #expect(vm.activeMidiNotes == [67])
        #expect(vm.scratchpad.hasContent)
    }

    @Test
    func midiHandleNoteOffNeverStopsThroughIPadSampler() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 80, source: .midi)
        vm.handleNoteOff(67, source: .midi)
        #expect(engine.stopTouchNoteCalls.isEmpty)
        #expect(vm.activeMidiNotes.isEmpty)
    }

    // MARK: - Chords

    @Test
    func threeSimultaneousMidiNotesProduceThreeScratchpadEntries() {
        let (vm, _, _) = makeVM()
        vm.handleNoteOn(60, velocity: 100, source: .midi)
        vm.handleNoteOn(64, velocity: 100, source: .midi)
        vm.handleNoteOn(67, velocity: 100, source: .midi)
        vm.handleNoteOff(60, source: .midi)
        vm.handleNoteOff(64, source: .midi)
        vm.handleNoteOff(67, source: .midi)
        #expect(vm.activeMidiNotes.isEmpty)
        // Each note materialises into scratchpad.notes once its note-off arrives.
        #expect(vm.scratchpad.notes.count == 3)
        let midis = Set(vm.scratchpad.notes.map { $0.midi })
        #expect(midis == [60, 64, 67])
    }

    // MARK: - MIDI velocity 0 routing

    @Test
    func midiVelocityZeroRoutesAsNoteOff() async {
        let (vm, engine, midi) = makeVM()
        vm.onAppear()
        engine.playTouchNoteCalls.removeAll()
        engine.stopTouchNoteCalls.removeAll()
        midi.fire(MIDIInputEvent(noteNumber: 60, velocity: 100))
        midi.fire(MIDIInputEvent(noteNumber: 60, velocity: 0))
        // Bookkeeping runs via Task { @MainActor } — drain twice so both
        // queued main-actor tasks complete.
        await Task.yield()
        await Task.yield()
        // MIDI input must never produce iPad audio.
        #expect(engine.playTouchNoteCalls.isEmpty)
        #expect(engine.stopTouchNoteCalls.isEmpty)
        #expect(vm.activeMidiNotes.isEmpty)
    }

    // MARK: - MIDI hot path: highlight bit flips on the MIDI thread

    @Test
    func midiOnNoteEventNeverCallsEngine() async {
        let (vm, engine, midi) = makeVM()
        vm.onAppear()
        engine.playTouchNoteCalls.removeAll()
        midi.fire(MIDIInputEvent(noteNumber: 67, velocity: 80))
        // The MIDI hot path must NOT play through the iPad sampler — the
        // external MIDI keyboard already produces sound.
        #expect(engine.playTouchNoteCalls.isEmpty)
        // Phase 2 (bookkeeping) hops to MainActor — drain to observe state.
        await Task.yield()
        await Task.yield()
        #expect(vm.activeMidiNotes == [67])
    }

    // MARK: - Lifecycle

    @Test
    func onDisappearStopsAllAndClearsMidiHandler() {
        let (vm, engine, midi) = makeVM()
        vm.onAppear()
        vm.handleNoteOn(60, velocity: 100, source: .midi)
        vm.onDisappear()
        #expect(engine.stopAllTouchNotesCallCount >= 1)
        #expect(midi.onNoteEvent == nil)
    }

    @Test
    func onAppearLoadsCurrentProgramAndAttachesMidiHandler() {
        let (vm, engine, midi) = makeVM()
        engine.loadProgramCalls.removeAll()
        vm.onAppear()
        #expect(engine.loadProgramCalls.count == 1)
        #expect(engine.loadProgramCalls[0].program == 0)  // default Acoustic Grand
        #expect(midi.onNoteEvent != nil)
    }

    // MARK: - attachEngine

    @Test
    func attachEngineSwapsAndReloadsProgram() {
        let initial = MockPlayTabAudioEngine()
        let real = MockPlayTabAudioEngine()
        let (vm, _, _) = makeVM(engine: initial)
        vm.attachEngine(real)
        #expect(real.loadProgramCalls.count == 1)
        #expect(real.loadProgramCalls[0].program == vm.currentInstrument)
    }

    @Test
    func attachEngineDoesNotRouteMIDIThroughSampler() {
        let initial = MockPlayTabAudioEngine()
        let real = MockPlayTabAudioEngine()
        let (vm, _, _) = makeVM(engine: initial)
        vm.attachEngine(real)
        real.loadProgramCalls.removeAll()  // clear the attach-time reload
        vm.handleNoteOn(60, velocity: 100, source: .midi)
        // MIDI never plays through the iPad sampler regardless of which
        // engine is attached.
        #expect(real.playTouchNoteCalls.isEmpty)
        #expect(initial.playTouchNoteCalls.isEmpty)
    }

    // MARK: - UserDefaults round-trip

    @Test
    func userDefaultsRoundTripInstrument() {
        let (vm1, _, _) = makeVM()
        vm1.setInstrument(25)
        // Recreate VM from a fresh dependency set; it should read 25 from UserDefaults.
        let coord = MIDINoteHighlightCoordinator()
        let vm2 = PlayTabViewModel(
            engine: MockPlayTabAudioEngine(),
            midiInput: MockMIDIInputProviding(),
            highlightCoordinator: coord
        )
        #expect(vm2.currentInstrument == 25)
    }

    // MARK: - Highlight observer wiring

    @Test
    func installHighlightObserverWiresCoordinatorCallback() {
        let coord = MIDINoteHighlightCoordinator()
        let vm = PlayTabViewModel(
            engine: MockPlayTabAudioEngine(),
            midiInput: MockMIDIInputProviding(),
            highlightCoordinator: coord
        )
        var received: Set<Int>?
        vm.installHighlightObserver { notes in
            received = notes
        }
        // The coordinator's `onActiveNotesChanged` is what `installHighlightObserver`
        // assigns. The CADisplayLink callback is what fires it; the unit-test
        // assertion is that the wiring assigned the closure (not the cadence).
        // Invoke directly to prove the callback the VM installed is the one the
        // coordinator will call.
        coord.onActiveNotesChanged?([60, 64, 67])
        #expect(received == [60, 64, 67])
    }

    // MARK: - Phase 1 / Phase 2 scratchpad capture

    @Test
    func phase2CaptureAppendsToScratchpad() async throws {
        let (vm, _, midi) = makeVM()
        vm.onAppear()

        // Fire a note-on then note-off via the mock — onNoteEvent runs
        // synchronously on the test thread (mimicking the CoreMIDI thread
        // pattern) and Phase 2 hops via Task { @MainActor in ... }.
        let onEvt = MIDIInputEvent(
            noteNumber: 60, velocity: 100, channel: 0,
            midiTimestamp: 1_000_000, timestamp: Date(),
            velocity16Bit: 12_800
        )
        let offEvt = MIDIInputEvent(
            noteNumber: 60, velocity: 0, channel: 0,
            midiTimestamp: 1_500_000, timestamp: Date(),
            velocity16Bit: 0
        )
        midi.fire(onEvt)
        midi.fire(offEvt)

        // Drain queued main-actor tasks (one per fire).
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.scratchpad.notes.count == 1)
        #expect(vm.scratchpad.notes[0].midi == 60)
        #expect(vm.scratchpad.notes[0].velocity == 100)
        #expect(vm.scratchpad.notes[0].velocity16Bit == 12_800)
        #expect(vm.scratchpad.notes[0].onTimeSec >= 0)
    }

    @Test
    func ccChangeTriggersSustainCapture() async throws {
        let (vm, _, midi) = makeVM()
        vm.onAppear()

        let cc = MIDIControlChangeEvent(
            controller: 64, value: 100, channel: 0,
            midiTimestamp: 1_000_000, timestamp: Date()
        )
        midi.onControlChangeEvent?(cc)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.scratchpad.sustain.contains(where: { $0.down }))
    }

    // MARK: - Soft / hard cap UI flags

    @Test
    func softCapBannerVisibleAt1500Notes() {
        let (vm, _, _) = makeVM()
        for i in 0..<1500 {
            vm.scratchpad.appendNoteOn(
                midi: 60, velocity: 90, velocity16: 0,
                channel: 0, onTimeSec: Double(i) * 0.01
            )
            vm.scratchpad.appendNoteOff(
                midi: 60, channel: 0,
                offTimeSec: Double(i) * 0.01 + 0.005
            )
        }
        #expect(vm.shouldShowSoftCapBanner)
        #expect(!vm.shouldShowHardCapModal)
    }

    @Test
    func softCapBannerHiddenWhenDismissed() {
        let (vm, _, _) = makeVM()
        for i in 0..<1500 {
            vm.scratchpad.appendNoteOn(
                midi: 60, velocity: 90, velocity16: 0,
                channel: 0, onTimeSec: Double(i) * 0.01
            )
            vm.scratchpad.appendNoteOff(
                midi: 60, channel: 0,
                offTimeSec: Double(i) * 0.01 + 0.005
            )
        }
        vm.softCapBannerDismissed = true
        #expect(!vm.shouldShowSoftCapBanner)
    }

    @Test
    func clearScratchpadResetsSoftCapDismissal() {
        let (vm, _, _) = makeVM()
        vm.softCapBannerDismissed = true
        vm.clearScratchpad()
        #expect(!vm.softCapBannerDismissed)
    }

    @Test
    func hardCapModalShownAt5000Notes() {
        let (vm, _, _) = makeVM()
        // ScratchpadState pauses capture at the hard cap, so we have to fill
        // up to (and including) the synthesised flush at 5000.
        for i in 0..<5000 {
            vm.scratchpad.appendNoteOn(
                midi: 60, velocity: 90, velocity16: 0,
                channel: 0, onTimeSec: Double(i) * 0.01
            )
            vm.scratchpad.appendNoteOff(
                midi: 60, channel: 0,
                offTimeSec: Double(i) * 0.01 + 0.005
            )
        }
        #expect(vm.shouldShowHardCapModal)
        // Soft-cap banner is suppressed once we cross into the hard cap so
        // the modal owns the surface.
        #expect(!vm.shouldShowSoftCapBanner)
    }

    @Test
    func userDefaultsRoundTripSaPitch() {
        let (vm1, _, _) = makeVM()
        vm1.setSaPitch(62)
        let coord = MIDINoteHighlightCoordinator()
        let vm2 = PlayTabViewModel(
            engine: MockPlayTabAudioEngine(),
            midiInput: MockMIDIInputProviding(),
            highlightCoordinator: coord
        )
        #expect(vm2.saPitch == 62)
    }
}
