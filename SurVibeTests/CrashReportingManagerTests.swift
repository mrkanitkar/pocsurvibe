import SVCore
import Testing

/// Tests for CrashReportingManager (MetricKit integration).
///
/// MetricKit delivers payloads asynchronously once per day, so these tests
/// verify the manager's lifecycle and state management rather than actual
/// diagnostic payloads (which require real device + 24-hour collection).
///
/// Serialized because tests share the `CrashReportingManager.shared` singleton.
@Suite(.serialized)
@MainActor
struct CrashReportingManagerTests {

    // MARK: - Singleton

    @Test("Shared instance exists")
    @MainActor
    func sharedInstanceExists() {
        let manager = CrashReportingManager.shared
        #expect(manager !== nil as AnyObject?)
    }

    @Test("Shared instance returns same object")
    @MainActor
    func sharedInstanceIsSameObject() {
        let first = CrashReportingManager.shared
        let second = CrashReportingManager.shared
        #expect(first === second)
    }

    // MARK: - Initial State

    @Test("Initial state is not active")
    @MainActor
    func initialStateIsNotActive() {
        let manager = CrashReportingManager.shared
        // Deactivate first in case a previous test activated it
        manager.deactivate()
        #expect(manager.isActive == false)
    }

    @Test("Payload counts are non-negative")
    @MainActor
    func initialPayloadCountsAreNonNegative() {
        let manager = CrashReportingManager.shared
        #expect(manager.diagnosticPayloadsReceived >= 0)
        #expect(manager.metricPayloadsReceived >= 0)
    }

    // MARK: - Activation / Deactivation

    @Test("Activate sets isActive to true")
    @MainActor
    func activateSetsIsActive() {
        let manager = CrashReportingManager.shared
        manager.deactivate()
        manager.activate()
        #expect(manager.isActive == true)
        manager.deactivate()
    }

    @Test("Deactivate clears isActive")
    @MainActor
    func deactivateClearsIsActive() {
        let manager = CrashReportingManager.shared
        manager.activate()
        manager.deactivate()
        #expect(manager.isActive == false)
    }

    @Test("Double activate is a no-op")
    @MainActor
    func doubleActivateIsNoOp() {
        let manager = CrashReportingManager.shared
        manager.deactivate()
        manager.activate()
        manager.activate()  // Second call should be a no-op
        #expect(manager.isActive == true)
        manager.deactivate()
    }

    @Test("Double deactivate is a no-op")
    @MainActor
    func doubleDeactivateIsNoOp() {
        let manager = CrashReportingManager.shared
        manager.activate()
        manager.deactivate()
        manager.deactivate()  // Second call should be a no-op
        #expect(manager.isActive == false)
    }

    @Test("Activate after deactivate reactivates")
    @MainActor
    func activateAfterDeactivateReactivates() {
        let manager = CrashReportingManager.shared
        manager.activate()
        manager.deactivate()
        manager.activate()
        #expect(manager.isActive == true)
        manager.deactivate()
    }
}
