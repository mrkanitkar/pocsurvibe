import AVFoundation
import os
import Testing

@testable import SVAudio

// MARK: - AudioSessionDeactivatingSpy

/// Records every `setActive(_:options:)` call so tests can assert options.
final class AudioSessionDeactivatingSpy: AudioSessionDeactivating, @unchecked Sendable {
    struct Call {
        let active: Bool
        let options: AVAudioSession.SetActiveOptions
    }

    private(set) var calls: [Call] = []

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        calls.append(Call(active: active, options: options))
    }
}

// MARK: - AudioSessionManager Tests

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

    /// Verifies Apple HIG compliance: deactivate always passes
    /// `.notifyOthersOnDeactivation` so other apps (Music, Podcasts, etc.)
    /// know to ramp their audio back up after SurVibe stops.
    /// See: https://developer.apple.com/documentation/avfaudio/avaudiosession/setactiveoptions/notifyothersondeactivation
    @Test("deactivate passes .notifyOthersOnDeactivation — Apple HIG compliance")
    @MainActor
    func deactivatePassesNotifyOthersOnDeactivation() {
        let spy = AudioSessionDeactivatingSpy()
        let manager = AudioSessionManager(deactivatingSession: spy)

        manager.deactivate()

        #expect(spy.calls.count == 1)
        #expect(spy.calls.first?.active == false)
        #expect(spy.calls.first?.options.contains(.notifyOthersOnDeactivation) == true)
    }

    @Test("deactivate passes .notifyOthersOnDeactivation on repeated calls")
    @MainActor
    func deactivateAlwaysPassesNotifyOthersOnDeactivation() {
        let spy = AudioSessionDeactivatingSpy()
        let manager = AudioSessionManager(deactivatingSession: spy)

        manager.deactivate()
        manager.deactivate()

        #expect(spy.calls.count == 2)
        #expect(spy.calls.allSatisfy { $0.options.contains(.notifyOthersOnDeactivation) })
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
        let receivedReason = OSAllocatedUnfairLock<AVAudioSession.RouteChangeReason?>(initialState: nil)
        manager.onRouteChangeWithReason = { reason in
            receivedReason.withLock { $0 = reason }
        }

        manager.handleRouteChange(reason: .oldDeviceUnavailable)
        #expect(receivedReason.withLock { $0 } == .oldDeviceUnavailable)

        manager.onRouteChangeWithReason = nil
    }

    @Test("handleRouteChange fires legacy onRouteChange alongside reason callback")
    @MainActor
    func routeChangeLegacyAndReasonBothFire() {
        let manager = AudioSessionManager.shared
        let legacyFired = OSAllocatedUnfairLock<Bool>(initialState: false)
        let receivedReason = OSAllocatedUnfairLock<AVAudioSession.RouteChangeReason?>(initialState: nil)

        manager.onRouteChange = { legacyFired.withLock { $0 = true } }
        manager.onRouteChangeWithReason = { reason in
            receivedReason.withLock { $0 = reason }
        }

        manager.handleRouteChange(reason: .newDeviceAvailable)

        #expect(legacyFired.withLock { $0 })
        #expect(receivedReason.withLock { $0 } == .newDeviceAvailable)

        manager.onRouteChange = nil
        manager.onRouteChangeWithReason = nil
    }

    @Test("handleRouteChange with nil reason fires legacy but not reason callback")
    @MainActor
    func routeChangeNilReasonSkipsReasonCallback() {
        let manager = AudioSessionManager.shared
        let legacyFired = OSAllocatedUnfairLock<Bool>(initialState: false)
        let reasonFired = OSAllocatedUnfairLock<Bool>(initialState: false)

        manager.onRouteChange = { legacyFired.withLock { $0 = true } }
        manager.onRouteChangeWithReason = { _ in reasonFired.withLock { $0 = true } }

        manager.handleRouteChange(reason: nil)

        #expect(legacyFired.withLock { $0 })
        #expect(!reasonFired.withLock { $0 })

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
        let beganFired = OSAllocatedUnfairLock<Bool>(initialState: false)

        manager.onInterruptionBegan = { beganFired.withLock { $0 = true } }
        defer { manager.onInterruptionBegan = nil }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.began.rawValue,
            optionsValue: 0
        )

        #expect(beganFired.withLock { $0 })
    }

    @Test("interruptionEndedFiresCallbackWithShouldResume — handleInterruption with .ended and .shouldResume option passes true")
    @MainActor
    func interruptionEndedFiresCallbackWithShouldResume() {
        let manager = AudioSessionManager.shared
        let receivedShouldResume = OSAllocatedUnfairLock<Bool?>(initialState: nil)

        manager.onInterruptionEnded = { shouldResume in
            receivedShouldResume.withLock { $0 = shouldResume }
        }
        defer { manager.onInterruptionEnded = nil }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.ended.rawValue,
            optionsValue: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        )

        #expect(receivedShouldResume.withLock { $0 } == true)
    }

    @Test("interruptionEndedFiresCallbackWithShouldResumefalse — handleInterruption with .ended and no options passes false")
    @MainActor
    func interruptionEndedFiresCallbackWithShouldResumeFalse() {
        let manager = AudioSessionManager.shared
        let receivedShouldResume = OSAllocatedUnfairLock<Bool?>(initialState: nil)

        manager.onInterruptionEnded = { shouldResume in
            receivedShouldResume.withLock { $0 = shouldResume }
        }
        defer { manager.onInterruptionEnded = nil }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.ended.rawValue,
            optionsValue: 0
        )

        #expect(receivedShouldResume.withLock { $0 } == false)
    }

    @Test("interruptionBeganDoesNotFireEndedCallback — .began type only fires onInterruptionBegan")
    @MainActor
    func interruptionBeganDoesNotFireEndedCallback() {
        let manager = AudioSessionManager.shared
        let endedFired = OSAllocatedUnfairLock<Bool>(initialState: false)

        manager.onInterruptionBegan = { }
        manager.onInterruptionEnded = { _ in endedFired.withLock { $0 = true } }
        defer {
            manager.onInterruptionBegan = nil
            manager.onInterruptionEnded = nil
        }

        manager.handleInterruption(
            typeValue: AVAudioSession.InterruptionType.began.rawValue,
            optionsValue: 0
        )

        #expect(!endedFired.withLock { $0 })
    }

    @Test("interruptionWithNilTypeValueIsIgnored — nil typeValue does not crash or fire callbacks")
    @MainActor
    func interruptionWithNilTypeValueIsIgnored() {
        let manager = AudioSessionManager.shared
        let beganFired = OSAllocatedUnfairLock<Bool>(initialState: false)
        let endedFired = OSAllocatedUnfairLock<Bool>(initialState: false)

        manager.onInterruptionBegan = { beganFired.withLock { $0 = true } }
        manager.onInterruptionEnded = { _ in endedFired.withLock { $0 = true } }
        defer {
            manager.onInterruptionBegan = nil
            manager.onInterruptionEnded = nil
        }

        manager.handleInterruption(typeValue: nil, optionsValue: nil)

        #expect(!beganFired.withLock { $0 })
        #expect(!endedFired.withLock { $0 })
    }
}
