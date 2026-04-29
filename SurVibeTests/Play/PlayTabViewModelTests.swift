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

    // MARK: - MIDI path: VM produces audio

    @Test
    func midiHandleNoteOnPlaysAudioWithVelocityPreserved() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 80, source: .midi)
        #expect(engine.playTouchNoteCalls.count == 1)
        #expect(engine.playTouchNoteCalls[0].midi == 67)
        #expect(engine.playTouchNoteCalls[0].velocity == 80)
        #expect(vm.recordedNotes.count == 1)
    }

    @Test
    func midiHandleNoteOffStopsAudio() {
        let (vm, engine, _) = makeVM()
        vm.handleNoteOn(67, velocity: 80, source: .midi)
        vm.handleNoteOff(67, source: .midi)
        #expect(engine.stopTouchNoteCalls == [67])
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
    func seventeenthNoteAudioPlaysButStripDoesNotGrow() {
        let (vm, engine, _) = makeVM()
        for n: UInt8 in 60..<76 {
            vm.handleNoteOn(n, velocity: 100, source: .midi)
            vm.handleNoteOff(n, source: .midi)
        }
        let playCallsBefore = engine.playTouchNoteCalls.count
        vm.handleNoteOn(80, velocity: 100, source: .midi)
        #expect(vm.recordedNotes.count == 16)
        #expect(engine.playTouchNoteCalls.count == playCallsBefore + 1)
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
        // The MIDI closure hops via Task { @MainActor } — yield twice so both
        // queued main-actor tasks have a chance to run.
        await Task.yield()
        await Task.yield()
        #expect(engine.playTouchNoteCalls.count == 1)
        #expect(engine.stopTouchNoteCalls == [60])
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
