import AVFoundation
import Testing

@testable import SVAudio

@Suite("AudioSessionManager Tests")
struct AudioSessionManagerTests {
    @Test("Singleton exists")
    @MainActor
    func singletonExists() {
        let manager = AudioSessionManager.shared
        #expect(manager != nil)
    }

    @Test("Sample rate returns a positive value")
    @MainActor
    func sampleRateIsPositive() {
        #expect(AudioSessionManager.shared.sampleRate > 0)
    }

    @Test("deactivate does not crash on unconfigured session")
    @MainActor
    func deactivateOnUnconfiguredSession() {
        // Calling deactivate without prior configure should log a warning
        // but not crash or throw.
        AudioSessionManager.shared.deactivate()
    }

    @Test("Interruption callbacks default to nil")
    @MainActor
    func interruptionCallbacksDefaultNil() {
        let manager = AudioSessionManager.shared
        #expect(manager.onInterruptionBegan == nil)
        #expect(manager.onInterruptionEnded == nil)
    }

    @Test("Route change callback defaults to nil")
    @MainActor
    func routeChangeCallbackDefaultsNil() {
        let manager = AudioSessionManager.shared
        #expect(manager.onRouteChange == nil)
    }

    @Test("Callbacks can be assigned and cleared")
    @MainActor
    func callbacksAssignableAndClearable() {
        let manager = AudioSessionManager.shared

        // Assign callbacks
        manager.onInterruptionBegan = { }
        manager.onInterruptionEnded = { _ in }
        manager.onRouteChange = { }
        manager.onRouteChangeWithReason = { _ in }

        #expect(manager.onInterruptionBegan != nil)
        #expect(manager.onInterruptionEnded != nil)
        #expect(manager.onRouteChange != nil)
        #expect(manager.onRouteChangeWithReason != nil)

        // Clear callbacks
        manager.onInterruptionBegan = nil
        manager.onInterruptionEnded = nil
        manager.onRouteChange = nil
        manager.onRouteChangeWithReason = nil

        #expect(manager.onInterruptionBegan == nil)
        #expect(manager.onInterruptionEnded == nil)
        #expect(manager.onRouteChange == nil)
        #expect(manager.onRouteChangeWithReason == nil)
    }

    @Test("onRouteChangeWithReason defaults to nil")
    @MainActor
    func routeChangeWithReasonDefaultsNil() {
        let manager = AudioSessionManager.shared
        #expect(manager.onRouteChangeWithReason == nil)
    }

    @Test("handleRouteChange fires onRouteChangeWithReason with correct reason")
    @MainActor
    func routeChangeWithReasonFires() {
        let manager = AudioSessionManager.shared
        var receivedReason: AVAudioSession.RouteChangeReason?
        manager.onRouteChangeWithReason = { reason in
            receivedReason = reason
        }

        manager.handleRouteChange(reason: .oldDeviceUnavailable)
        #expect(receivedReason == .oldDeviceUnavailable)

        // Clean up
        manager.onRouteChangeWithReason = nil
    }

    @Test("handleRouteChange fires legacy onRouteChange alongside reason callback")
    @MainActor
    func routeChangeLegacyAndReasonBothFire() {
        let manager = AudioSessionManager.shared
        var legacyFired = false
        var receivedReason: AVAudioSession.RouteChangeReason?

        manager.onRouteChange = { legacyFired = true }
        manager.onRouteChangeWithReason = { reason in
            receivedReason = reason
        }

        manager.handleRouteChange(reason: .newDeviceAvailable)

        #expect(legacyFired)
        #expect(receivedReason == .newDeviceAvailable)

        // Clean up
        manager.onRouteChange = nil
        manager.onRouteChangeWithReason = nil
    }

    @Test("handleRouteChange with nil reason fires legacy but not reason callback")
    @MainActor
    func routeChangeNilReasonSkipsReasonCallback() {
        let manager = AudioSessionManager.shared
        var legacyFired = false
        var reasonFired = false

        manager.onRouteChange = { legacyFired = true }
        manager.onRouteChangeWithReason = { _ in reasonFired = true }

        manager.handleRouteChange(reason: nil)

        #expect(legacyFired)
        #expect(!reasonFired)

        // Clean up
        manager.onRouteChange = nil
        manager.onRouteChangeWithReason = nil
    }

    @Test("Buffer grant tier defaults to unknown before configuration")
    @MainActor
    func bufferGrantTierDefaultsToUnknown() {
        // Before configuration, lastBufferGrantTier should be .unknown.
        // We cannot call configureForPlayback() in SPM tests (no AVAudioSession
        // on macOS), so we verify the default state and enum cases.
        let manager = AudioSessionManager.shared
        #expect(manager.lastBufferGrantTier == .unknown)
    }

    @Test("BufferGrantTier enum has all expected cases")
    func bufferGrantTierCases() {
        // Verify the enum compiles with all four expected cases.
        let tiers: [BufferGrantTier] = [.unknown, .excellent, .acceptable, .degraded]
        #expect(tiers.count == 4)
        #expect(tiers[0] == .unknown)
        #expect(tiers[1] == .excellent)
        #expect(tiers[2] == .acceptable)
        #expect(tiers[3] == .degraded)
    }

    @Test("BufferGrantTier conforms to Sendable")
    func bufferGrantTierIsSendable() {
        // Verify Sendable conformance by passing across a sendability boundary.
        let tier: BufferGrantTier = .excellent
        let sendable: any Sendable = tier
        #expect(sendable is BufferGrantTier)
    }

    // MARK: - Interruption Handler Tests (A10 gap)

    @Test("interruptionBeganFiresCallback — handleInterruption with .began type invokes onInterruptionBegan")
    @MainActor
    func interruptionBeganFiresCallback() {
        let manager = AudioSessionManager.shared
        var beganFired = false

        manager.onInterruptionBegan = { beganFired = true }
        defer { manager.onInterruptionBegan = nil }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.began.rawValue,
            optionsValue: 0
        )

        #expect(beganFired)
    }

    @Test("interruptionEndedFiresCallbackWithShouldResume — handleInterruption with .ended and .shouldResume option passes true")
    @MainActor
    func interruptionEndedFiresCallbackWithShouldResume() {
        let manager = AudioSessionManager.shared
        var receivedShouldResume: Bool?

        manager.onInterruptionEnded = { shouldResume in
            receivedShouldResume = shouldResume
        }
        defer { manager.onInterruptionEnded = nil }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.ended.rawValue,
            optionsValue: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        )

        #expect(receivedShouldResume == true)
    }

    @Test("interruptionEndedFiresCallbackWithShouldResumefalse — handleInterruption with .ended and no options passes false")
    @MainActor
    func interruptionEndedFiresCallbackWithShouldResumeFalse() {
        let manager = AudioSessionManager.shared
        var receivedShouldResume: Bool?

        manager.onInterruptionEnded = { shouldResume in
            receivedShouldResume = shouldResume
        }
        defer { manager.onInterruptionEnded = nil }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.ended.rawValue,
            optionsValue: 0
        )

        #expect(receivedShouldResume == false)
    }

    @Test("interruptionBeganDoesNotFireEndedCallback — .began type only fires onInterruptionBegan")
    @MainActor
    func interruptionBeganDoesNotFireEndedCallback() {
        let manager = AudioSessionManager.shared
        var endedFired = false

        manager.onInterruptionBegan = { }
        manager.onInterruptionEnded = { _ in endedFired = true }
        defer {
            manager.onInterruptionBegan = nil
            manager.onInterruptionEnded = nil
        }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.began.rawValue,
            optionsValue: 0
        )

        #expect(!endedFired)
    }

    @Test("interruptionWithNilTypeValueIsIgnored — nil typeValue does not crash or fire callbacks")
    @MainActor
    func interruptionWithNilTypeValueIsIgnored() {
        let manager = AudioSessionManager.shared
        var beganFired = false
        var endedFired = false

        manager.onInterruptionBegan = { beganFired = true }
        manager.onInterruptionEnded = { _ in endedFired = true }
        defer {
            manager.onInterruptionBegan = nil
            manager.onInterruptionEnded = nil
        }

        manager.handleInterruption(typeValue: nil, optionsValue: nil)

        #expect(!beganFired)
        #expect(!endedFired)
    }
}
