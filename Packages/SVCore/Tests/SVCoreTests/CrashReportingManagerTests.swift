import Testing
@testable import SVCore

/// Tests for CrashReportingManager (MetricKit integration).
///
/// MetricKit delivers payloads asynchronously once per day, so these tests
/// verify the manager's lifecycle and state management rather than actual
/// diagnostic payloads (which require real device + 24-hour collection).
@MainActor
struct CrashReportingManagerTests {

    // MARK: - Singleton

    @Test func sharedInstanceExists() {
        let manager = CrashReportingManager.shared
        #expect(manager !== nil as AnyObject?)
    }

    @Test func sharedInstanceIsSameObject() {
        let first = CrashReportingManager.shared
        let second = CrashReportingManager.shared
        #expect(first === second)
    }

    // MARK: - Initial State

    @Test func initialStateIsNotActive() async {
        let manager = CrashReportingManager.shared
        // Deactivate first in case a previous test activated it
        manager.deactivate()
        #expect(manager.isActive == false)
    }

    @Test func initialPayloadCountsAreNonNegative() async {
        let manager = CrashReportingManager.shared
        #expect(manager.diagnosticPayloadsReceived >= 0)
        #expect(manager.metricPayloadsReceived >= 0)
    }

    // MARK: - Activation / Deactivation

    @Test func activateSetsIsActive() async {
        let manager = CrashReportingManager.shared
        manager.deactivate()
        manager.activate()
        #expect(manager.isActive == true)
        manager.deactivate()
    }

    @Test func deactivateClearsIsActive() async {
        let manager = CrashReportingManager.shared
        manager.activate()
        manager.deactivate()
        #expect(manager.isActive == false)
    }

    @Test func doubleActivateIsNoOp() async {
        let manager = CrashReportingManager.shared
        manager.deactivate()
        manager.activate()
        manager.activate()  // Second call should be a no-op
        #expect(manager.isActive == true)
        manager.deactivate()
    }

    @Test func doubleDeactivateIsNoOp() async {
        let manager = CrashReportingManager.shared
        manager.activate()
        manager.deactivate()
        manager.deactivate()  // Second call should be a no-op
        #expect(manager.isActive == false)
    }

    @Test func activateAfterDeactivateReactivates() async {
        let manager = CrashReportingManager.shared
        manager.activate()
        manager.deactivate()
        manager.activate()
        #expect(manager.isActive == true)
        manager.deactivate()
    }
}
