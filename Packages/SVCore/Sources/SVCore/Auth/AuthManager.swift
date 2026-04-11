import AuthenticationServices
import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

// MARK: - AuthManagerProtocol

/// Protocol defining authentication operations for Sign in with Apple.
///
/// Conforming types must be `@MainActor`-isolated for UI-safe state access.
/// Enables dependency injection and testability via mock implementations.
public protocol AuthManagerProtocol: Sendable {
    /// Initiates the Sign in with Apple flow.
    ///
    /// - Returns: The authenticated `AppleUser` on success.
    /// - Throws: `AuthError` if the sign-in fails or is cancelled.
    @MainActor func signInWithApple() async throws -> AppleUser

    /// Convenience sign-in method (calls `signInWithApple()`).
    @MainActor func signIn() async throws

    /// Signs out the current user and clears stored credentials.
    @MainActor func signOut()

    /// Restores a previous session from Keychain if a valid credential exists.
    @MainActor func restoreSession() async

    /// Checks the credential state for a given Apple user identifier.
    ///
    /// - Parameter userIdentifier: The Apple user identifier to check.
    /// - Throws: `AuthError` if the credential is revoked or invalid.
    @MainActor func checkCredentialState(userIdentifier: String) async throws

    /// Whether the user is currently authenticated.
    @MainActor var isAuthenticated: Bool { get }
}

// MARK: - AuthManager

/// Manages Sign in with Apple authentication, session persistence, and credential monitoring.
///
/// Uses `ASAuthorizationController` delegate callbacks bridged to Swift concurrency via
/// `CheckedContinuation`. The user identifier is persisted in Keychain for session
/// restoration across app launches. Credential revocation is monitored via
/// `ASAuthorizationAppleIDProvider.credentialRevokedNotification`.
///
/// - Important: Inherits from `NSObject` to conform to `ASAuthorizationControllerDelegate`
///   and `ASAuthorizationControllerPresentationContextProviding`.
@MainActor
@Observable
public final class AuthManager: NSObject, AuthManagerProtocol,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{

    // MARK: - Singleton

    /// Shared singleton instance.
    ///
    /// Uses `MainActor.assumeIsolated` because Swift's static let guarantees
    /// thread-safe one-time initialization, and the app configures this on
    /// the main thread during launch.
    nonisolated(unsafe) public static let shared: AuthManager = {
        MainActor.assumeIsolated {
            AuthManager()
        }
    }()

    // MARK: - Properties

    /// The current authentication state, observed by SwiftUI views.
    public private(set) var authState: AuthState = .anonymous

    /// Whether the user is currently authenticated.
    public var isAuthenticated: Bool {
        if case .authenticated = authState {
            return true
        }
        return false
    }

    /// The currently authenticated user, or `nil` if not authenticated.
    public var currentUser: AppleUser? {
        if case .authenticated(let user) = authState {
            return user
        }
        return nil
    }

    /// Logger for authentication events.
    private static let logger = Logger(
        subsystem: "com.survibe",
        category: "Auth"
    )

    /// Continuation bridging ASAuthorizationControllerDelegate → async/await.
    private var signInContinuation: CheckedContinuation<AppleUser, any Error>?

    // MARK: - Initialization

    /// Creates the auth manager and registers for credential revocation notifications.
    override private init() {
        super.init()
        observeCredentialRevocation()
    }

    // MARK: - Public Methods

    /// Initiates the Sign in with Apple flow using `ASAuthorizationController`.
    ///
    /// Creates an Apple ID authorization request with `.fullName` and `.email` scopes,
    /// presents the system sign-in sheet, and bridges the delegate result to async.
    ///
    /// - Returns: The authenticated `AppleUser`.
    /// - Throws: `AuthError.cancelled` if user dismisses, other `AuthError` on failure.
    @discardableResult
    public func signInWithApple() async throws -> AppleUser {
        authState = .authenticating
        AnalyticsManager.shared.track(.signInStarted)
        Self.logger.info("Sign in with Apple flow started.")

        do {
            let user = try await withCheckedThrowingContinuation { continuation in
                self.signInContinuation = continuation

                let appleIDProvider = ASAuthorizationAppleIDProvider()
                let request = appleIDProvider.createRequest()
                request.requestedScopes = [.fullName, .email]

                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }

            persistAndTrackSuccess(user: user)
            return user
        } catch let error as AuthError {
            handleSignInAuthError(error)
            throw error
        } catch {
            let authError = AuthError.unknown(error.localizedDescription)
            authState = .error(authError)
            AnalyticsManager.shared.track(
                .signInFailed,
                properties: ["error": error.localizedDescription]
            )
            Self.logger.error("Sign in with Apple failed: \(error.localizedDescription)")
            throw authError
        }
    }

    /// Persist a successful sign-in to Keychain and update state.
    private func persistAndTrackSuccess(user: AppleUser) {
        do {
            try KeychainHelper.storeUserIdentifier(user.userIdentifier)
        } catch {
            Self.logger.error(
                "Failed to store user identifier in Keychain: \(error.localizedDescription)"
            )
        }

        authState = .authenticated(user)
        AnalyticsManager.shared.track(
            .signInCompleted,
            properties: ["has_name": !user.displayName.isEmpty]
        )
        Self.logger.info("Sign in with Apple completed successfully.")
    }

    /// Handle an `AuthError` thrown during sign-in.
    private func handleSignInAuthError(_ error: AuthError) {
        switch error {
        case .cancelled:
            authState = .anonymous
            AnalyticsManager.shared.track(.signInCancelled)
            Self.logger.info("Sign in with Apple was cancelled by user.")
        default:
            authState = .error(error)
            AnalyticsManager.shared.track(
                .signInFailed,
                properties: ["error": error.errorDescription ?? "unknown"]
            )
            Self.logger.error(
                "Sign in with Apple failed: \(error.errorDescription ?? "unknown")"
            )
        }
    }

    /// Convenience sign-in for protocol conformance.
    public func signIn() async throws {
        _ = try await signInWithApple()
    }

    /// Signs out the current user and clears stored credentials.
    public func signOut() {
        do {
            try KeychainHelper.deleteUserIdentifier()
        } catch {
            Self.logger.error(
                "Failed to delete user identifier from Keychain: \(error.localizedDescription)"
            )
        }

        authState = .signedOut
        AnalyticsManager.shared.reset()
        AnalyticsManager.shared.track(.signOutCompleted)
        Self.logger.info("User signed out.")
    }

    /// Restores a previous session from Keychain if a valid credential exists.
    ///
    /// Creates a minimal `AppleUser` on restore (identifier only — Apple does not
    /// return name/email on subsequent checks).
    public func restoreSession() async {
        Self.logger.info("Attempting to restore session from Keychain.")

        let userIdentifier: String
        do {
            userIdentifier = try KeychainHelper.retrieveUserIdentifier()
        } catch {
            Self.logger.info("No stored credential found — remaining anonymous.")
            return
        }

        do {
            let credentialState = try await fetchCredentialState(
                forUserID: userIdentifier
            )

            switch credentialState {
            case .authorized:
                let restoredUser = AppleUser(
                    userIdentifier: userIdentifier,
                    displayName: "",
                    email: nil
                )
                authState = .authenticated(restoredUser)
                AnalyticsManager.shared.identify(userId: userIdentifier)
                Self.logger.info("Session restored successfully.")

            case .revoked:
                Self.logger.warning("Credential revoked — clearing stored session.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous
                AnalyticsManager.shared.track(.credentialRevoked)

            case .notFound:
                Self.logger.info("Credential not found — clearing stored session.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous

            case .transferred:
                Self.logger.info("Credential transferred — clearing stored session.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous

            @unknown default:
                Self.logger.warning("Unknown credential state — clearing stored session.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous
            }
        } catch {
            Self.logger.error(
                "Failed to check credential state: \(error.localizedDescription)"
            )
        }
    }

    /// Checks the credential state for a given Apple user identifier.
    ///
    /// - Parameter userIdentifier: The Apple user identifier to check.
    /// - Throws: `AuthError.credentialRevoked` if revoked, `AuthError.unknown` on failure.
    public func checkCredentialState(userIdentifier: String) async throws {
        do {
            let credentialState = try await fetchCredentialState(
                forUserID: userIdentifier
            )

            switch credentialState {
            case .authorized:
                Self.logger.info("Credential is authorized.")

            case .revoked:
                Self.logger.warning("Credential has been revoked.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .error(.credentialRevoked)
                AnalyticsManager.shared.track(.credentialRevoked)
                throw AuthError.credentialRevoked

            case .notFound:
                Self.logger.info("Credential not found.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous

            case .transferred:
                Self.logger.info("Credential transferred to another team.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous

            @unknown default:
                Self.logger.warning("Unknown credential state encountered.")
                try? KeychainHelper.deleteUserIdentifier()
                authState = .anonymous
            }
        } catch let error as AuthError {
            throw error
        } catch {
            Self.logger.error("Credential state check failed: \(error.localizedDescription)")
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    /// Fetches the credential state for a given user identifier using a continuation wrapper.
    ///
    /// The completion-handler API is used because `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)`
    /// async overload may not be available under strict concurrency in SPM packages.
    ///
    /// - Parameter userIdentifier: The Apple user identifier to check.
    /// - Returns: The `ASAuthorizationAppleIDProvider.CredentialState`.
    /// - Throws: The error returned by the provider.
    private func fetchCredentialState(
        forUserID userIdentifier: String
    ) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(
                forUserID: userIdentifier
            ) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    /// Registers an observer for Apple ID credential revocation notifications.
    private func observeCredentialRevocation() {
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Self.logger.warning("Received credential revocation notification.")
                try? KeychainHelper.deleteUserIdentifier()
                self.authState = .error(.credentialRevoked)
                AnalyticsManager.shared.track(.credentialRevoked)
            }
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    /// Handles successful Sign in with Apple authorization.
    nonisolated public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
            as? ASAuthorizationAppleIDCredential
        else {
            let error = AuthError.unknown("Unexpected credential type received.")
            Task { @MainActor [weak self] in
                self?.signInContinuation?.resume(throwing: error)
                self?.signInContinuation = nil
            }
            return
        }

        let userIdentifier = credential.user
        let email = credential.email

        var displayName = ""
        if let nameComponents = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: nameComponents)
            if !formatted.trimmingCharacters(in: .whitespaces).isEmpty {
                displayName = formatted
            }
        }

        let user = AppleUser(
            userIdentifier: userIdentifier,
            displayName: displayName,
            email: email
        )

        Task { @MainActor [weak self] in
            self?.signInContinuation?.resume(returning: user)
            self?.signInContinuation = nil
        }
    }

    /// Handles failed Sign in with Apple authorization.
    nonisolated public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        let authError: AuthError

        if let asError = error as? ASAuthorizationError {
            switch asError.code {
            case .canceled:
                authError = .cancelled
            case .failed:
                authError = .networkError(asError.localizedDescription)
            case .invalidResponse:
                authError = .unknown("Invalid response from Apple.")
            case .notHandled:
                authError = .unknown("Authorization request not handled.")
            case .notInteractive:
                authError = .unknown("Authorization requires user interaction.")
            case .matchedExcludedCredential:
                authError = .unknown("Credential was excluded.")
            @unknown default:
                authError = .unknown(asError.localizedDescription)
            }
        } else {
            authError = .unknown(error.localizedDescription)
        }

        Task { @MainActor [weak self] in
            self?.signInContinuation?.resume(throwing: authError)
            self?.signInContinuation = nil
        }
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    /// Provides the presentation anchor window for the Sign in with Apple sheet.
    nonisolated public func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            return scene?.keyWindow ?? ASPresentationAnchor()
            #else
            return ASPresentationAnchor()
            #endif
        }
    }
}
