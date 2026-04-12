import os

// MARK: - Centralized Logger Factory

extension Logger {

    // MARK: - Subsystem

    /// The shared subsystem identifier used by all SurVibe loggers.
    ///
    /// Matches the app's bundle identifier (`com.survibe`). Centralizing this
    /// constant ensures a single rename propagates to every logger in the
    /// project, across all 7 SPM packages.
    private static let subsystem = "com.survibe"

    // MARK: - Factory

    /// Creates a logger scoped to the SurVibe subsystem.
    ///
    /// Provides a single source of truth for the subsystem string so that a
    /// bundle-identifier rename only requires updating one constant.
    /// Each call site supplies its own category (typically the type name).
    ///
    /// ```swift
    /// private static let logger = Logger.survibe(category: "AudioEngine")
    /// ```
    ///
    /// - Parameter category: A short, PascalCase label that groups related log
    ///   messages (e.g. `"PitchDetector"`, `"ImportPipeline"`).
    /// - Returns: A configured `Logger` instance for the SurVibe subsystem.
    public static func survibe(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
