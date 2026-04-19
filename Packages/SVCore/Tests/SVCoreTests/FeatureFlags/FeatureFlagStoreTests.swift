// Packages/SVCore/Tests/SVCoreTests/FeatureFlags/FeatureFlagStoreTests.swift
import Foundation
import Testing
@testable import SVCore

@MainActor
@Suite("FeatureFlagStore")
struct FeatureFlagStoreTests {

    /// Test harness: isolated UserDefaults + mock analytics for each test (no cross-test pollution).
    private struct Harness {
        let store: FeatureFlagStore
        let defaults: UserDefaults
        let provider: MockAnalyticsProvider
    }

    /// Creates a fresh, isolated `Harness` backed by a unique UserDefaults suite.
    private func makeHarness(suite: String = UUID().uuidString) -> Harness {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let provider = MockAnalyticsProvider()
        let store = FeatureFlagStore(defaults: defaults, analytics: provider)
        return Harness(store: store, defaults: defaults, provider: provider)
    }

    @Test func everyFlagDefaultsToFalse() {
        let h = makeHarness()
        for flag in FeatureFlag.allCases {
            #expect(h.store.isEnabled(flag) == false, "\(flag) should default to false")
        }
    }

    @Test func setEnabledRoundTripsThroughDefaults() {
        let h = makeHarness()
        h.store.setEnabled(.onDeviceAI, true)
        #expect(h.store.isEnabled(.onDeviceAI) == true)
        #expect(h.defaults.bool(forKey: "ff.onDeviceAI") == true)

        h.store.setEnabled(.onDeviceAI, false)
        #expect(h.store.isEnabled(.onDeviceAI) == false)
        #expect(h.defaults.bool(forKey: "ff.onDeviceAI") == false)
    }

    @Test func togglingOneFlagDoesNotAffectOthers() {
        let h = makeHarness()
        h.store.setEnabled(.playAlongViewModelV2, true)
        #expect(h.store.isEnabled(.playAlongViewModelV2) == true)
        #expect(h.store.isEnabled(.onDeviceAI) == false)
        #expect(h.store.isEnabled(.macDestination) == false)
    }

    @Test func togglingFiresAnalyticsEvent() {
        let h = makeHarness()
        h.store.setEnabled(.onDeviceAI, true)

        let event = h.provider.tracked.first { $0.event == .featureFlagToggled }
        #expect(event != nil, "featureFlagToggled should be tracked")
        #expect(event?.properties?["flag"] as? String == "onDeviceAI")
        #expect(event?.properties?["enabled"] as? Bool == true)
    }
}
