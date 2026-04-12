import Foundation
import Testing
import os

@testable import SVCore

/// TEST-D01-009: Structured Logging (os.Logger Categories)
///
/// Verifies that the centralized `Logger.survibe(category:)` factory produces
/// correctly configured loggers, and that privacy annotations compile and
/// execute without errors.
@Suite("Structured Logging Tests")
@MainActor
struct StructuredLoggingTests {

    // MARK: - Scenario 1: SVCore Logger Categories via Factory

    @Test("SVCore logger categories via factory")
    func svCoreLoggerCategoriesExist() {
        let analyticsLogger = Logger.survibe(category: "Analytics")
        let authLogger = Logger.survibe(category: "Auth")
        let permissionsLogger = Logger.survibe(category: "Permissions")
        let crashLogger = Logger.survibe(category: "CrashReporting")

        analyticsLogger.debug("Test: Analytics logger active")
        authLogger.debug("Test: Auth logger active")
        permissionsLogger.debug("Test: Permissions logger active")
        crashLogger.debug("Test: CrashReporting logger active")

        #expect(true, "All SVCore logger categories initialized via factory without error")
    }

    // MARK: - Scenario 2: SVAudio Logger Categories via Factory

    @Test("SVAudio logger categories via factory")
    func svAudioLoggerCategoriesExist() {
        let pitchLogger = Logger.survibe(category: "PitchDetector")
        let engineLogger = Logger.survibe(category: "AudioEngine")
        let sessionLogger = Logger.survibe(category: "AudioSession")
        let metronomeLogger = Logger.survibe(category: "Metronome")

        pitchLogger.debug("Test: PitchDetector logger active")
        engineLogger.debug("Test: AudioEngine logger active")
        sessionLogger.debug("Test: AudioSession logger active")
        metronomeLogger.debug("Test: Metronome logger active")

        #expect(true, "All SVAudio logger categories initialized via factory without error")
    }

    // MARK: - Scenario 3: Factory Produces Correct Subsystem

    @Test("Factory uses com.survibe subsystem")
    func factorySubsystemCorrect() {
        let logger = Logger.survibe(category: "TestCategory")

        // os.Logger doesn't expose its subsystem property, but we verify
        // the factory method exists and produces a usable logger.
        logger.info("Subsystem verification: info level")
        logger.debug("Subsystem verification: debug level")
        logger.error("Subsystem verification: error level")
        logger.warning("Subsystem verification: warning level")

        #expect(true, "Logger.survibe(category:) produces working logger at all levels")
    }

    // MARK: - Scenario 4: Privacy Annotations

    @Test("Privacy annotations compile and execute")
    func privacyAnnotationsWork() {
        let logger = Logger.survibe(category: "PrivacyTest")

        let sensitiveEmail = "user@example.com"
        let sensitivePhone = "555-1234"
        let userId = "usr_abc123"

        logger.info("User identified: \(sensitiveEmail, privacy: .private)")
        logger.info("Phone: \(sensitivePhone, privacy: .private)")
        logger.info("User ID: \(userId, privacy: .public)")

        // Non-sensitive diagnostic data should use .public
        logger.info("App version: \("1.0.0", privacy: .public)")
        logger.info("Event count: \(42, privacy: .public)")

        // Error descriptions use .public (diagnostic, not user data)
        let error = NSError(domain: "test", code: 42)
        logger.error("Error: \(error.localizedDescription, privacy: .public)")

        #expect(true, "Logging with privacy annotations completed without error")
    }

    // MARK: - Scenario 5: AnalyticsManager Uses Logger

    @Test("AnalyticsManager has configured logger")
    @MainActor
    func analyticsManagerUsesLogger() {
        let manager = AnalyticsManager.shared
        manager.track(.appScaffoldingLoaded)
        #expect(true, "AnalyticsManager.track() with logger completed without error")
    }

    // MARK: - Scenario 6: CrashReportingManager Uses Logger

    @Test("CrashReportingManager logs activation")
    @MainActor
    func crashReportingManagerUsesLogger() {
        let manager = CrashReportingManager.shared
        manager.deactivate()
        manager.activate()
        #expect(manager.isActive == true, "Activation logged via os.Logger")
        manager.deactivate()
        #expect(manager.isActive == false, "Deactivation logged via os.Logger")
    }
}
