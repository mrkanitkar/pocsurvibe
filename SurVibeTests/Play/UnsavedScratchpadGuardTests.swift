import Foundation
import Testing

@testable import SurVibe

@MainActor
struct UnsavedScratchpadGuardTests {
    @Test func raiseSetsPendingAction() {
        let guardObj = UnsavedScratchpadGuard()
        #expect(guardObj.pending == nil)
        guardObj.raise(.newSession) { _ in }
        #expect(guardObj.pending == .newSession)
    }

    @Test func raiseTabChangeCarriesDestination() {
        let guardObj = UnsavedScratchpadGuard()
        guardObj.raise(.tabChange(to: .songs)) { _ in }
        #expect(guardObj.pending == .tabChange(to: .songs))
    }

    @Test func answerSaveInvokesResolverAndClears() {
        let guardObj = UnsavedScratchpadGuard()
        var got: GuardOutcome?
        guardObj.raise(.newSession) { got = $0 }
        guardObj.answer(.save)
        #expect(got == .save)
        #expect(guardObj.pending == nil)
        #expect(guardObj.onResolve == nil)
    }

    @Test func answerDiscardInvokesResolverAndClears() {
        let guardObj = UnsavedScratchpadGuard()
        var got: GuardOutcome?
        guardObj.raise(.tabChange(to: .home)) { got = $0 }
        guardObj.answer(.discard)
        #expect(got == .discard)
        #expect(guardObj.pending == nil)
    }

    @Test func answerCancelInvokesResolverAndClears() {
        let guardObj = UnsavedScratchpadGuard()
        var got: GuardOutcome?
        guardObj.raise(.tabChange(to: .home)) { got = $0 }
        guardObj.answer(.cancel)
        #expect(got == .cancel)
        #expect(guardObj.pending == nil)
    }

    @Test func answerWithNoPendingIsNoop() {
        let guardObj = UnsavedScratchpadGuard()
        guardObj.answer(.save)  // does not crash, does not invoke anything
        #expect(guardObj.pending == nil)
    }

    @Test func resolverInvokedExactlyOnce() {
        let guardObj = UnsavedScratchpadGuard()
        var count = 0
        guardObj.raise(.newSession) { _ in count += 1 }
        guardObj.answer(.save)
        guardObj.answer(.save)  // second answer must not fire stale resolver
        #expect(count == 1)
    }

    @Test func raiseReplacesPriorPending() {
        let guardObj = UnsavedScratchpadGuard()
        var firstCount = 0
        var secondGot: GuardOutcome?
        guardObj.raise(.newSession) { _ in firstCount += 1 }
        guardObj.raise(.tabChange(to: .profile)) { secondGot = $0 }
        guardObj.answer(.discard)
        #expect(firstCount == 0)  // first resolver overwritten, never fired
        #expect(secondGot == .discard)
    }
}
