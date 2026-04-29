import Foundation
import SVAudio
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
        #expect(vm.recordedNotes.count == 1)
        #expect(vm.recordedNotes[0].midi == 67)
    }

    @Test
    func touchHandleNoteOffDoesNotStopAudio() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 100, source: .touch)
        vm.handleNoteOff(67, source: .touch)
        #expect(engine.stopTouchNoteCalls.isEmpty)
        #expect(vm.activeMidiNotes.isEmpty)
        #expect(vm.recordedNotes.count == 1)  // release does not record
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
        #expect(vm.recordedNotes.count == 1)
    }

    @Test
    func midiHandleNoteOffNeverStopsThroughIPadSampler() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 80, source: .midi)
        vm.handleNoteOff(67, source: .midi)
        #expect(engine.stopTouchNoteCalls.isEmpty)
        #expect(vm.activeMidiNotes.isEmpty)
    }

    // MARK: - Re-trigger guard

    @Test
    func reTriggerSameNoteDoesNotDuplicateStrip() {
        let (vm, _, _) = makeVM()
        vm.handleNoteOn(67, velocity: 100, source: .midi)
        vm.handleNoteOn(67, velocity: 100, source: .midi)
        #expect(vm.recordedNotes.count == 1)
    }

    // MARK: - Strip cap

    @Test
    func sixteenNotesFillsTheStrip() {
        let (vm, _, _) = makeVM()
        for n: UInt8 in 60..<76 {
            vm.handleNoteOn(n, velocity: 100, source: .midi)
            vm.handleNoteOff(n, source: .midi)
        }
        #expect(vm.recordedNotes.count == 16)
        #expect(vm.isStripFull)
    }

    @Test
    func seventeenthMidiNoteIsHighlightedButStripDoesNotGrow() {
        let (vm, engine, _) = makeVM()
        for n: UInt8 in 60..<76 {
            vm.handleNoteOn(n, velocity: 100, source: .midi)
            vm.handleNoteOff(n, source: .midi)
        }
        vm.handleNoteOn(80, velocity: 100, source: .midi)
        #expect(vm.recordedNotes.count == 16)
        // MIDI never plays through the iPad sampler; the strip overflow
        // does not change that.
        #expect(engine.playTouchNoteCalls.isEmpty)
        #expect(vm.activeMidiNotes.contains(80))
    }

    // MARK: - Clear

    @Test
    func clearStripEmptiesStripWithoutTouchingActiveNotes() {
        let (vm, _, _) = makeVM()
        vm.handleNoteOn(60, velocity: 100, source: .midi)
        vm.clearStrip()
        #expect(vm.recordedNotes.isEmpty)
        #expect(vm.activeMidiNotes == [60])
    }

    // MARK: - Chords

    @Test
    func threeSimultaneousMidiNotesProduceThreeStripEntries() {
        let (vm, _, _) = makeVM()
        vm.handleNoteOn(60, velocity: 100, source: .midi)
        vm.handleNoteOn(64, velocity: 100, source: .midi)
        vm.handleNoteOn(67, velocity: 100, source: .midi)
        #expect(vm.activeMidiNotes == [60, 64, 67])
        #expect(vm.recordedNotes.count == 3)
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
