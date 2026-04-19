// Packages/SVCore/Tests/SVCoreTests/FeatureFlags/FeatureFlagStoreTests.swift
import Foundation
import Testing
@testable import SVCore

@MainActor
@Suite("FeatureFlagStore")
struct FeatureFlagStoreTests {

    /// Helper: isolated UserDefaults + mock analytics for each test (no cross-test pollution).
    private func makeStore(
        suite: String = UUID().uuidString
    ) -> (FeatureFlagStore, UserDefaults, MockAnalyticsProvider) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let provider = MockAnalyticsProvider()
        let store = FeatureFlagStore(defaults: defaults, analytics: provider)
        return (store, defaults, provider)
    }

    @Test func everyFlagDefaultsToFalse() {
        let (store, _, _) = makeStore()
        for flag in FeatureFlag.allCases {
            #expect(store.isEnabled(flag) == false, "\(flag) should default to false")
        }
    }

    @Test func setEnabledRoundTripsThroughDefaults() {
        let (store, defaults, _) = makeStore()
        store.setEnabled(.onDeviceAI, true)
        #expect(store.isEnabled(.onDeviceAI) == true)
        #expect(defaults.bool(forKey: "ff.onDeviceAI") == true)

        store.setEnabled(.onDeviceAI, false)
        #expect(store.isEnabled(.onDeviceAI) == false)
        #expect(defaults.bool(forKey: "ff.onDeviceAI") == false)
    }

    @Test func togglingOneFlagDoesNotAffectOthers() {
        let (store, _, _) = makeStore()
        store.setEnabled(.playAlongViewModelV2, true)
        #expect(store.isEnabled(.playAlongViewModelV2) == true)
        #expect(store.isEnabled(.onDeviceAI) == false)
        #expect(store.isEnabled(.macDestination) == false)
    }

    @Test func togglingFiresAnalyticsEvent() {
        let (store, _, provider) = makeStore()

        store.setEnabled(.onDeviceAI, true)

        let event = provider.tracked.first { $0.event == .featureFlagToggled }
        #expect(event != nil, "featureFlagToggled should be tracked")
        #expect(event?.properties?["flag"] as? String == "onDeviceAI")
        #expect(event?.properties?["enabled"] as? Bool == true)
    }
}
