import Foundation
import Testing
@testable import SurVibe

@MainActor
struct TanpuraControllerTests {
    @Test func defaultStateIsOffAtC4() {
        let c = TanpuraController()
        #expect(c.isTanpuraEnabled == false)
        #expect(abs(c.saGridHz - 261.6255653) < 0.0001)
        #expect(c.saCentsOffset == 0)
        #expect(abs(c.volume - 0.3) < 0.001)
    }

    @Test func effectiveSaHzEqualsGridWhenCentsZero() {
        let c = TanpuraController()
        c.setSa(pitchClass: 0, octave: 4)
        #expect(abs(c.effectiveSaHz - 261.6255653) < 0.0001)
    }

    @Test func setSaChangesGridAndPitchClass() {
        let c = TanpuraController()
        c.setSa(pitchClass: 1, octave: 4)  // C#4
        #expect(abs(c.saGridHz - 277.1826) < 0.001)
        #expect(c.saPitchClass == 1)
        #expect(c.saOctave == 4)
    }

    @Test func centsOffsetModulatesEffectiveHz() {
        let c = TanpuraController()
        c.setSa(pitchClass: 0, octave: 4)          // 261.6256
        c.setCentsOffset(12)                        // +12 cents
        // 261.6256 * 2^(12/1200) ≈ 263.443
        #expect(abs(c.effectiveSaHz - 263.443) < 0.01)
    }

    @Test func centsOffsetClampedToPlusMinus50() {
        let c = TanpuraController()
        c.setCentsOffset(100)
        #expect(c.saCentsOffset == 50)
        c.setCentsOffset(-100)
        #expect(c.saCentsOffset == -50)
    }

    @Test func roundTripGridAndCentsSurviveComposeDecompose() {
        // (C#4, +10) → 277.1826 * 2^(10/1200) ≈ 278.787
        let c = TanpuraController()
        c.setSa(pitchClass: 1, octave: 4)
        c.setCentsOffset(10)
        let effective = c.effectiveSaHz

        // Simulate persistence round-trip via the static helper.
        let decomposed = TanpuraController.decompose(effectiveSaHz: effective)
        #expect(decomposed.pitchClass == 1)
        #expect(decomposed.octave == 4)
        #expect(decomposed.cents == 10)
    }

    @Test func setSoundEnabledFalseDoesNotClearIntent() {
        let c = TanpuraController()
        c.toggleEnabled()                           // intent = on
        c.setSoundEnabled(false)                    // master mute
        #expect(c.isTanpuraEnabled == true)         // intent preserved
        #expect(c.effectiveIsPlaying == false)      // but effectively silent
    }

    @Test func effectiveIsPlayingRequiresBothFlags() {
        let c = TanpuraController()
        #expect(c.effectiveIsPlaying == false)
        c.toggleEnabled()
        c.setSoundEnabled(true)
        #expect(c.effectiveIsPlaying == true)
        c.setSoundEnabled(false)
        #expect(c.effectiveIsPlaying == false)
    }

    @Test func seedFromPreferredHzDecomposesCorrectly() {
        let c = TanpuraController()
        // 278.787 ≈ (C#4, +10)
        c.seed(preferredSaHz: 278.787)
        #expect(c.saPitchClass == 1)
        #expect(c.saOctave == 4)
        #expect(c.saCentsOffset == 10)
    }

    @Test func seedWithNilUsesSongDefault() {
        let c = TanpuraController()
        c.seed(preferredSaHz: nil, songDefaultHz: 293.6648)  // D4
        #expect(c.saPitchClass == 2)
        #expect(c.saOctave == 4)
        #expect(c.saCentsOffset == 0)
    }
}
