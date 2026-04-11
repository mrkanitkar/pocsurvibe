import Testing

@testable import SurVibe

@MainActor
struct SargamFadeManagerTests {
    /// Helper: creates a manager with autoHide explicitly enabled.
    /// @AppStorage may not read UserDefaults in test context.
    private func makeManager(autoHide: Bool = true) -> SargamFadeManager {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = autoHide
        return manager
    }

    // MARK: - Threshold Tests (autoHide ON — labels fade with accuracy)

    @Test func accuracyZeroYieldsFullOpacity() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 0.0)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test func accuracyPerfectYieldsZeroOpacity() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 0.0)
    }

    @Test func accuracyBelowThresholdYieldsFullOpacity() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 0.5)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test func accuracyAtSixtyYieldsReducedOpacity() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 0.6)
        #expect(manager.labelOpacity == 0.6)
    }

    @Test func accuracyAtEightyYieldsLowOpacity() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 0.8)
        #expect(manager.labelOpacity == 0.3)
    }

    @Test func accuracyAtNinetyFiveYieldsZeroOpacity() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 0.95)
        #expect(manager.labelOpacity == 0.0)
    }

    // MARK: - Toggle Tests (autoHide OFF — labels always visible)

    @Test func toggleOffAlwaysYieldsFullOpacityRegardlessOfAccuracy() {
        let manager = makeManager(autoHide: false)

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
        let manager = makeManager()
        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 0.0)

        manager.reset()
        #expect(manager.labelOpacity == 1.0)
        #expect(manager.currentAccuracy == 0.0)
    }

    // MARK: - Clamping Tests

    @Test func accuracyAboveOneIsClamped() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: 1.5)
        #expect(manager.currentAccuracy == 1.0)
        #expect(manager.labelOpacity == 0.0)
    }

    @Test func accuracyBelowZeroIsClamped() {
        let manager = makeManager()
        manager.updateOpacity(accuracy: -0.5)
        #expect(manager.currentAccuracy == 0.0)
        #expect(manager.labelOpacity == 1.0)
    }
}
