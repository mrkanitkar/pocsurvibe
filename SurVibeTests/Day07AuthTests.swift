import Foundation
import Testing

@testable import SVCore

// MARK: - AuthState Tests

@MainActor
struct AuthStateTests {
    @Test func equalityAnonymous() {
        #expect(AuthState.anonymous == AuthState.anonymous)
    }

    @Test func equalityAuthenticating() {
        #expect(AuthState.authenticating == AuthState.authenticating)
    }

    @Test func equalityAuthenticated() {
        let user1 = AppleUser(userIdentifier: "abc", displayName: "Test")
        let user2 = AppleUser(userIdentifier: "abc", displayName: "Test")
        #expect(AuthState.authenticated(user1) == AuthState.authenticated(user2))
    }

    @Test func inequalityDifferentUsers() {
        let user1 = AppleUser(userIdentifier: "abc", displayName: "Test")
        let user2 = AppleUser(userIdentifier: "xyz", displayName: "Other")
        #expect(AuthState.authenticated(user1) != AuthState.authenticated(user2))
    }

    @Test func inequalityDifferentCases() {
        #expect(AuthState.anonymous != AuthState.authenticating)
        #expect(AuthState.anonymous != AuthState.signedOut)
    }

    @Test func errorEquality() {
        #expect(AuthState.error(.cancelled) == AuthState.error(.cancelled))
        #expect(AuthState.error(.cancelled) != AuthState.error(.credentialRevoked))
    }
}

// MARK: - AuthError Tests

@MainActor
struct AuthErrorTests {
    @Test func errorDescriptions() {
        #expect(AuthError.cancelled.errorDescription != nil)
        #expect(AuthError.credentialRevoked.errorDescription != nil)
        #expect(AuthError.cloudKitUnavailable.errorDescription != nil)
        #expect(AuthError.networkError("timeout").errorDescription != nil)
        #expect(AuthError.unknown("oops").errorDescription != nil)
    }

    @Test func networkErrorContainsDetail() {
        let error = AuthError.networkError("connection reset")
        #expect(error.errorDescription?.contains("connection reset") == true)
    }

    @Test func unknownErrorContainsDetail() {
        let error = AuthError.unknown("something went wrong")
        #expect(error.errorDescription?.contains("something went wrong") == true)
    }

    @Test func equatable() {
        #expect(AuthError.cancelled == AuthError.cancelled)
        #expect(AuthError.cancelled != AuthError.credentialRevoked)
        #expect(AuthError.networkError("a") == AuthError.networkError("a"))
        #expect(AuthError.networkError("a") != AuthError.networkError("b"))
    }
}

// MARK: - AppleUser Tests

@MainActor
struct AppleUserTests {
    @Test func creation() {
        let user = AppleUser(
            userIdentifier: "user123",
            displayName: "Test User",
            email: "test@example.com"
        )
        #expect(user.userIdentifier == "user123")
        #expect(user.displayName == "Test User")
        #expect(user.email == "test@example.com")
    }

    @Test func creationWithoutEmail() {
        let user = AppleUser(
            userIdentifier: "user456",
            displayName: "No Email"
        )
        #expect(user.email == nil)
    }

    @Test func equatable() {
        let user1 = AppleUser(userIdentifier: "a", displayName: "A")
        let user2 = AppleUser(userIdentifier: "a", displayName: "A")
        let user3 = AppleUser(userIdentifier: "b", displayName: "B")
        #expect(user1 == user2)
        #expect(user1 != user3)
    }

    @Test func codable() throws {
        let user = AppleUser(
            userIdentifier: "encoded",
            displayName: "Codable Test",
            email: "test@test.com"
        )
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(AppleUser.self, from: data)
        #expect(decoded == user)
    }
}

// MARK: - SignInTrigger Tests

@MainActor
struct SignInTriggerTests {
    @Test func allCases() {
        let triggers: [SignInTrigger] = [.premiumSong, .cloudSync, .profile, .settings]
        for trigger in triggers {
            #expect(!trigger.promptTitle.isEmpty)
            #expect(!trigger.promptMessage.isEmpty)
        }
    }

    @Test func premiumSongTriggerMentionsUnlock() {
        #expect(SignInTrigger.premiumSong.promptTitle.contains("Premium"))
    }

    @Test func cloudSyncTriggerMentionsSync() {
        #expect(SignInTrigger.cloudSync.promptTitle.contains("Sync"))
    }

    @Test func identifiableById() {
        #expect(SignInTrigger.premiumSong.id == "premiumSong")
        #expect(SignInTrigger.cloudSync.id == "cloudSync")
    }
}
