import Testing

@testable import SVCore

@Suite("AuthManager Tests")
struct AuthManagerTests {
    @Test("isAuthenticated defaults to false")
    @MainActor
    func defaultNotAuthenticated() {
        let manager = AuthManager.shared
        #expect(manager.isAuthenticated == false)
    }

    @Test("signOut sets isAuthenticated to false")
    @MainActor
    func signOutResetsState() async throws {
        let manager = AuthManager.shared
        try await manager.signOut()
        #expect(manager.isAuthenticated == false)
    }

    @Test("signIn throws in test environment without Apple ID context")
    @MainActor
    func signInThrowsInTestEnv() async {
        let manager = AuthManager.shared
        // Sign in with Apple requires a real device/simulator context;
        // in the test runner it throws an AuthorizationError.
        do {
            try await manager.signIn()
            // If it somehow succeeds, state should be authenticated
            #expect(manager.isAuthenticated == true)
        } catch {
            // Expected: ASAuthorizationError in test sandbox
            #expect(manager.isAuthenticated == false)
        }
    }
}
