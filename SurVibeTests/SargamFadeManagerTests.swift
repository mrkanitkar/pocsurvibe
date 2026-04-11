import Testing

@testable import SurVibe

@MainActor
struct SargamFadeManagerTests {
    // MARK: - Threshold Tests

    @Test func accuracyZeroYieldsFullOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 0.0)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test func accuracyPerfectYieldsZeroOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 0.0)
    }

    @Test func accuracyBelowThresholdYieldsFullOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 0.5)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test func accuracyAtSixtyYieldsReducedOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 0.6)
        #expect(manager.labelOpacity == 0.6)
    }

    @Test func accuracyAtEightyYieldsLowOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 0.8)
        #expect(manager.labelOpacity == 0.3)
    }

    @Test func accuracyAtNinetyFiveYieldsZeroOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 0.95)
        #expect(manager.labelOpacity == 0.0)
    }

    // MARK: - Toggle Tests

    @Test func toggleOffAlwaysYieldsFullOpacityRegardlessOfAccuracy() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = false

        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 1.0)

        manager.updateOpacity(accuracy: 0.95)
        #expect(manager.labelOpacity == 1.0)

        manager.updateOpacity(accuracy: 0.8)
        #expect(manager.labelOpacity == 1.0)

        manager.updateOpacity(accuracy: 0.0)
        #expect(manager.labelOpacity == 1.0)
    }

    // MARK: - Reset Tests

    @Test func resetRestoresFullOpacity() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 0.0)

        manager.reset()
        #expect(manager.labelOpacity == 1.0)
        #expect(manager.currentAccuracy == 0.0)
    }

    // MARK: - Clamping Tests

    @Test func accuracyAboveOneIsClamped() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: 1.5)
        #expect(manager.currentAccuracy == 1.0)
        #expect(manager.labelOpacity == 0.0)
    }

    @Test func accuracyBelowZeroIsClamped() {
        let manager = SargamFadeManager()
        manager.updateOpacity(accuracy: -0.5)
        #expect(manager.currentAccuracy == 0.0)
        #expect(manager.labelOpacity == 1.0)
    }
}
