import Foundation
import Testing

@testable import SurVibe

// MARK: - PlayAlongToolbar Wave 4 D1 state tests

/// Tests for the Wave 4 D1 toolbar-state properties on `PlayAlongViewModel`.
///
/// These are pure state-binding assertion tests — no SwiftUI snapshots, no
/// audio engine work. The view model is constructed with mocks so the suite
/// runs deterministically and hardware-free.
@MainActor
struct PlayAlongToolbarStateTests {

    /// Build a `PlayAlongViewModel` wired with hardware-free mocks.
    private func makeViewModel() -> PlayAlongViewModel {
        PlayAlongViewModel(
            soundFont: MockSoundFontPlayer(),
            audioEngine: MockAudioEngineProvider(),
            metronome: MockMetronomePlayer(),
            clock: TestClock()
        )
    }

    @Test func defaultBackingModeIsOn() {
        let vm = makeViewModel()
        #expect(vm.backingMode == .on)
    }

    @Test func defaultTempoScaleIs1_0() {
        let vm = makeViewModel()
        #expect(vm.tempoScale == 1.0)
    }

    @Test func defaultPracticeModeIsBoth() {
        let vm = makeViewModel()
        #expect(vm.practiceMode == .both)
    }

    @Test func defaultClickLevelIsNormal() {
        let vm = makeViewModel()
        #expect(vm.clickLevel == .normal)
    }

    @Test func loopRegionDefaultsToNil() {
        let vm = makeViewModel()
        #expect(vm.loopRegion == nil)
    }

    @Test func hasMultipleStavesDefaultsToFalse() {
        let vm = makeViewModel()
        #expect(vm.hasMultipleStaves == false)
    }

    @Test func showLoopBuilderDefaultsToFalse() {
        let vm = makeViewModel()
        #expect(vm.showLoopBuilder == false)
    }

    @Test func tempoScaleClampsTo0_5To1_5() {
        let vm = makeViewModel()

        vm.tempoScale = 0.4
        #expect(vm.tempoScale == 0.5)

        vm.tempoScale = 1.6
        #expect(vm.tempoScale == 1.5)

        // Values inside the range are preserved.
        vm.tempoScale = 0.75
        #expect(vm.tempoScale == 0.75)
    }

    @Test func backingModeIsCaseIterable() {
        #expect(PlayAlongViewModel.BackingMode.allCases.count == 3)
        #expect(PlayAlongViewModel.BackingMode.allCases.contains(.on))
        #expect(PlayAlongViewModel.BackingMode.allCases.contains(.click))
        #expect(PlayAlongViewModel.BackingMode.allCases.contains(.off))
    }

    @Test func clickLevelIsCaseIterable() {
        #expect(PlayAlongViewModel.ClickLevel.allCases.count == 3)
        #expect(PlayAlongViewModel.ClickLevel.allCases.contains(.soft))
        #expect(PlayAlongViewModel.ClickLevel.allCases.contains(.normal))
        #expect(PlayAlongViewModel.ClickLevel.allCases.contains(.loud))
    }

    @Test func loopRegionRoundTrips() {
        let vm = makeViewModel()
        let region = LoopRegion(startMeasure: 5, endMeasure: 8)
        vm.loopRegion = region
        #expect(vm.loopRegion == region)
        vm.loopRegion = nil
        #expect(vm.loopRegion == nil)
    }
}
