import Foundation

/// Typed key/value store for user-facing preferences (Appearance, Privacy, etc.).
///
/// Defined here so packages (SVAI, SVAudio) can read preferences without
/// importing the app target. The concrete implementation — `@AppStorage`-backed
/// or `ModelContext`-backed — lives in the app target and is injected at
/// composition time by the first consumer sub-project (SP-4 / SP-5).
public protocol PreferenceStoring: Sendable {
    /// Reads the value for `key`, returning `default` if no value is stored.
    func value<T: Sendable>(for key: String, default: T) -> T
    /// Writes `value` for `key`, replacing any prior value.
    func setValue<T: Sendable>(_ value: T, for key: String)
}
