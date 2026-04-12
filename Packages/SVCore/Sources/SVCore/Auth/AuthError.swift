import Foundation

/// Errors that can occur during Sign in with Apple authentication.
///
/// All associated values use `String` (not `Error`) to maintain `Sendable` conformance
/// across isolation boundaries.
public enum AuthError: SurVibeError, Equatable {
    /// A network error prevented authentication.
    case networkError(String)
    /// The user cancelled the Sign in with Apple flow.
    case cancelled
    /// The user's Apple ID credential was revoked.
    case credentialRevoked
    /// CloudKit is unavailable (no iCloud account or restricted).
    case cloudKitUnavailable
    /// An unknown error occurred.
    case unknown(String)

    // MARK: - SurVibeError

    public var domain: String { "SVCore" }

    public var code: String {
        switch self {
        case .networkError: "network_error"
        case .cancelled: "cancelled"
        case .credentialRevoked: "credential_revoked"
        case .cloudKitUnavailable: "cloudkit_unavailable"
        case .unknown: "unknown"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .networkError(let detail):
            "Network error: \(detail)"
        case .cancelled:
            "Sign in was cancelled."
        case .credentialRevoked:
            "Your Apple ID credential has been revoked. Please sign in again."
        case .cloudKitUnavailable:
            "iCloud is unavailable. Please check your iCloud settings."
        case .unknown(let detail):
            "Authentication error: \(detail)"
        }
    }
}
