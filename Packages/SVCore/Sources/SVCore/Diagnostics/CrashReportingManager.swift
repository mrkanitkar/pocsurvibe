import Foundation
import MetricKit
import os

/// Manages crash reporting and performance diagnostics via Apple MetricKit.
///
/// Subscribes to `MXMetricManager` to receive daily diagnostic and metric payloads.
/// Crash reports, hang diagnostics, CPU exceptions, and disk write exceptions
/// are logged via `os.Logger` for Xcode Organizer and on-device Console inspection.
/// Zero third-party dependencies — uses Apple-native MetricKit only.
///
/// - Important: Call `activate()` once at app launch to begin receiving reports.
///   MetricKit delivers payloads at most once per day, typically within 24 hours
///   of the events occurring.
@MainActor
public final class CrashReportingManager: NSObject {

    // MARK: - Singleton

    /// Shared crash reporting manager instance.
    public static let shared = CrashReportingManager()

    // MARK: - Properties

    /// Whether the manager has been activated and is receiving reports.
    public private(set) var isActive: Bool = false

    /// Number of diagnostic payloads received since activation.
    public private(set) var diagnosticPayloadsReceived: Int = 0

    /// Number of metric payloads received since activation.
    public private(set) var metricPayloadsReceived: Int = 0

    private static let logger = Logger.survibe(category: "CrashReporting")

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Activate crash reporting by subscribing to MetricKit.
    ///
    /// Call once during app launch, after analytics configuration.
    /// Safe to call multiple times — subsequent calls are no-ops.
    public func activate() {
        guard !isActive else {
            Self.logger.debug("CrashReportingManager already active, skipping.")
            return
        }

        MXMetricManager.shared.add(self)
        isActive = true
        Self.logger.info("CrashReportingManager activated — subscribed to MetricKit.")

        // Process any past diagnostic payloads that arrived before activation
        let pastDiagnostics = MXMetricManager.shared.pastDiagnosticPayloads
        if !pastDiagnostics.isEmpty {
            Self.logger.info(
                "Processing \(pastDiagnostics.count) past diagnostic payload(s)."
            )
            logDiagnosticPayloads(pastDiagnostics)
        }
    }

    /// Deactivate crash reporting and unsubscribe from MetricKit.
    ///
    /// Typically only needed for testing or when the user opts out of diagnostics.
    public func deactivate() {
        guard isActive else { return }
        MXMetricManager.shared.remove(self)
        isActive = false
        Self.logger.info("CrashReportingManager deactivated.")
    }

    // MARK: - Private Methods

    /// Extracts Sendable summary data from diagnostic payloads for cross-isolation logging.
    nonisolated private static func extractDiagnosticSummaries(
        _ payloads: [MXDiagnosticPayload]
    ) -> [DiagnosticSummary] {
        payloads.map { payload in
            DiagnosticSummary(
                crashCount: payload.crashDiagnostics?.count ?? 0,
                hangCount: payload.hangDiagnostics?.count ?? 0,
                cpuExceptionCount: payload.cpuExceptionDiagnostics?.count ?? 0,
                diskWriteExceptionCount: payload.diskWriteExceptionDiagnostics?.count ?? 0,
                jsonString: String(data: payload.jsonRepresentation(), encoding: .utf8)
            )
        }
    }

    /// Extracts Sendable summary data from metric payloads for cross-isolation logging.
    nonisolated private static func extractMetricSummaries(
        _ payloads: [MXMetricPayload]
    ) -> [MetricSummary] {
        payloads.map { payload in
            MetricSummary(
                hasLaunchMetrics: payload.applicationLaunchMetrics != nil,
                hasResponsivenessMetrics: payload.applicationResponsivenessMetrics != nil,
                hasMemoryMetrics: payload.memoryMetrics != nil,
                jsonString: String(data: payload.jsonRepresentation(), encoding: .utf8)
            )
        }
    }

    /// Logs diagnostic payloads directly (call from MainActor context only).
    private func logDiagnosticPayloads(_ payloads: [MXDiagnosticPayload]) {
        let summaries = Self.extractDiagnosticSummaries(payloads)
        logDiagnosticSummaries(summaries)
    }

    /// Logs extracted diagnostic summaries via os.Logger.
    private func logDiagnosticSummaries(_ summaries: [DiagnosticSummary]) {
        for summary in summaries {
            if summary.crashCount > 0 {
                Self.logger.error(
                    "Crash diagnostics received: \(summary.crashCount) report(s)."
                )
            }
            if summary.hangCount > 0 {
                Self.logger.warning(
                    "Hang diagnostics: \(summary.hangCount) report(s)."
                )
            }
            if summary.cpuExceptionCount > 0 {
                Self.logger.warning(
                    "CPU exception diagnostics: \(summary.cpuExceptionCount) report(s)."
                )
            }
            if summary.diskWriteExceptionCount > 0 {
                Self.logger.warning(
                    "Disk write exception diagnostics: \(summary.diskWriteExceptionCount) report(s)."
                )
            }
            if let json = summary.jsonString {
                Self.logger.debug("Diagnostic payload JSON: \(json, privacy: .private)")
            }
        }
    }

    /// Logs extracted metric summaries via os.Logger.
    private func logMetricSummaries(_ summaries: [MetricSummary]) {
        for summary in summaries {
            if summary.hasLaunchMetrics {
                Self.logger.info("App launch metrics received.")
            }
            if summary.hasResponsivenessMetrics {
                Self.logger.info("Responsiveness metrics received.")
            }
            if summary.hasMemoryMetrics {
                Self.logger.info("Memory metrics received.")
            }
            if let json = summary.jsonString {
                Self.logger.debug("Metric payload JSON: \(json, privacy: .private)")
            }
        }
    }
}

// MARK: - Sendable Summary Types

/// Thread-safe summary extracted from MXDiagnosticPayload.
private struct DiagnosticSummary: Sendable {
    let crashCount: Int
    let hangCount: Int
    let cpuExceptionCount: Int
    let diskWriteExceptionCount: Int
    let jsonString: String?
}

/// Thread-safe summary extracted from MXMetricPayload.
private struct MetricSummary: Sendable {
    let hasLaunchMetrics: Bool
    let hasResponsivenessMetrics: Bool
    let hasMemoryMetrics: Bool
    let jsonString: String?
}

// MARK: - MXMetricManagerSubscriber

extension CrashReportingManager: MXMetricManagerSubscriber {

    /// Receives daily diagnostic reports from MetricKit.
    ///
    /// Called at most once per day with crash reports, hang diagnostics,
    /// CPU exceptions, and disk write exceptions from the past 24 hours.
    nonisolated public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Extract Sendable data before crossing isolation boundary
        let summaries = Self.extractDiagnosticSummaries(payloads)
        let count = payloads.count
        Task { @MainActor in
            self.diagnosticPayloadsReceived += count
            Self.logger.info(
                "Received \(count) diagnostic payload(s) (total: \(self.diagnosticPayloadsReceived))."
            )
            self.logDiagnosticSummaries(summaries)
        }
    }

    /// Receives daily metric reports from MetricKit.
    ///
    /// Called at most once per day with aggregated performance metrics
    /// including app launch time, hang rate, memory peaks, and CPU usage.
    nonisolated public func didReceive(_ payloads: [MXMetricPayload]) {
        // Extract Sendable data before crossing isolation boundary
        let summaries = Self.extractMetricSummaries(payloads)
        let count = payloads.count
        Task { @MainActor in
            self.metricPayloadsReceived += count
            Self.logger.info(
                "Received \(count) metric payload(s) (total: \(self.metricPayloadsReceived))."
            )
            self.logMetricSummaries(summaries)
        }
    }
}
