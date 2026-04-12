import Foundation
import os
import SVCore

/// On-device AI provider using Apple's FoundationModels framework.
/// Full implementation in Phase 2.
public final class OnDeviceAIProvider: AIProvider {
    private static let logger = Logger.survibe(category: "OnDeviceAI")

    public let name = "On-Device"

    public init() {}

    public var isAvailable: Bool {
        Self.logger.debug("On-device AI availability checked")
        // Phase 2: Check FoundationModels availability
        return false
    }

    public func generate(prompt: String) async throws -> String {
        Self.logger.info("On-device generate called, prompt length=\(prompt.count, privacy: .public)")
        // Phase 2: Use FoundationModels for on-device inference
        return ""
    }
}
