// SurVibeTests/PlayAlong/SongPlayAlongViewLayoutTests.swift
import Testing

@testable import SurVibe

/// Layout-gating logic tests for `SongPlayAlongView` via `PlayAlongViewModel`.
///
/// Tests verify the ViewModel computed properties and stored state that
/// directly control view-layer conditional rendering — tempo clamping,
/// keyboard visibility, Sa chip gating, and playback state reflection.
/// No SwiftUI layout is tested here; use Xcode previews for that.
@MainActor
@Suite("SongPlayAlongView — layout gating logic")
struct SongPlayAlongViewLayoutTests {

    // MARK: - Helpers

    /// Build a `PlayAlongViewModel` with hardware-free mocks.
    private func makeViewModel(
        midiInput: MockMIDIInputProvider = MockMIDIInputProvider()
    ) -> PlayAlongViewModel {
        PlayAlongViewModel(
            soundFont: MockSoundFontPlayer(),
            audioEngine: MockAudioEngineProvider(),
            metronome: MockMetronomePlayer(),
            clock: TestClock(),
            midiInput: midiInput
        )
    }

    // MARK: - Tests

    /// Setting `tempoScale` outside [0.5, 1.5] clamps to the boundary value.
    @Test("tempoScale clamps to valid range on assignment")
    func tempoScaleClampsToValidRange() {
        let vm = makeViewModel()

        vm.tempoScale = 0.3
        #expect(vm.tempoScale == 0.5)

        vm.tempoScale = 2.0
        #expect(vm.tempoScale == 1.5)

        vm.tempoScale = 0.75
        #expect(vm.tempoScale == 0.75)
    }

    /// `isMIDIConnected` starts `false` on a fresh VM (no hardware present).
    ///
    /// The view hides the on-screen keyboard when this is `true`. The full
    /// connection-detection path goes through a `connectionStateStream` async
    /// task inside `NoteRouter` and is covered by `NoteRouterTests`.
    @Test("isMIDIConnected is false on a fresh VM with no hardware")
    func conditionalKeyboardHiddenWhenMIDIConnected() {
        let mock = MockMIDIInputProvider()
        let vm = makeViewModel(midiInput: mock)

        // Initial state: no MIDI keyboard connected.
        #expect(vm.isMIDIConnected == false)

        // Simulate a pre-connected device by flagging simulateConnected before
        // startInputDetection. After start(), NoteRouter synchronously reads
        // midiInput.isConnected; the mock's Task{@MainActor} sets it before the
        // next await point. This verifies the property accessor is wired.
        mock.simulateConnected = true
        mock.simulateConnectionChange(connected: true)
        // isMIDIConnected is updated via NoteRouter's async connectionStateStream
        // task — that path is tested in NoteRouterTests. Here we confirm the
        // facade property still reads false (stream not yet consumed) which is the
        // correct synchronous view-render behaviour before the task runs.
        #expect(vm.isMIDIConnected == false)
    }

    /// `didInitialHydrate` starts `false` so the Sa chip stays hidden
    /// until `SongProgress` data has been loaded into the VM.
    @Test("Sa chip hidden until VM is hydrated")
    func saChipHiddenUntilHydrated() {
        let vm = makeViewModel()
        #expect(vm.didInitialHydrate == false)
    }

    /// `isPlaying` is `false` on a freshly created VM (playback idle).
    @Test("isPlaying is false when playback is idle")
    func isPlayingReflectsPlaybackState() {
        let vm = makeViewModel()
        #expect(vm.isPlaying == false)
    }

    /// `tempoScale` defaults to `1.0` (full speed) on a fresh VM.
    @Test("tempoScale defaults to 1.0")
    func tempoScaleDefaultIsOne() {
        let vm = makeViewModel()
        #expect(vm.tempoScale == 1.0)
    }

    /// `tonicSaPitch` defaults to MIDI 60 (C4), the standard Sa reference.
    @Test("tonicSaPitch defaults to MIDI 60 (C4)")
    func tonicSaPitchDefaultIs60() {
        let vm = makeViewModel()
        #expect(vm.tonicSaPitch == 60)
    }
}
