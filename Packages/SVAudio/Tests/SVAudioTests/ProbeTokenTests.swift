import Testing
@testable import SVAudio

struct ProbeTokenTests {

    @Test func freshTokenHasAllZeroTimestamps() {
        let token = ProbeToken()
        #expect(token.t0 == 0)
        #expect(token.t1 == 0)
        #expect(token.t2 == 0)
        #expect(token.t3 == 0)
    }

    @Test func stampSetsCorrectStage() {
        var token = ProbeToken()
        token.stamp(.inputReceived)
        #expect(token.t0 > 0)
        #expect(token.t1 == 0)

        token.stamp(.dspComplete)
        #expect(token.t1 > 0)
        #expect(token.t1 >= token.t0)

        token.stamp(.matchComplete)
        #expect(token.t2 > 0)
        #expect(token.t2 >= token.t1)

        token.stamp(.framePresented)
        #expect(token.t3 > 0)
        #expect(token.t3 >= token.t2)
    }

    @Test func elapsedReturnsZeroWhenIncomplete() {
        let token = ProbeToken()
        #expect(token.elapsedNanoseconds == nil)
    }

    @Test func elapsedReturnsPositiveWhenComplete() {
        var token = ProbeToken()
        token.stamp(.inputReceived)
        // Simulate some work
        for _ in 0..<1000 { _ = Int.random(in: 0..<100) }
        token.stamp(.dspComplete)
        token.stamp(.matchComplete)
        token.stamp(.framePresented)

        let elapsed = token.elapsedNanoseconds
        #expect(elapsed != nil)
        #expect(elapsed! > 0)
    }

    @Test func isCompleteReflectsAllStamped() {
        var token = ProbeToken()
        #expect(!token.isComplete)

        token.stamp(.inputReceived)
        #expect(!token.isComplete)

        token.stamp(.dspComplete)
        #expect(!token.isComplete)

        token.stamp(.matchComplete)
        #expect(!token.isComplete)

        token.stamp(.framePresented)
        #expect(token.isComplete)
    }

    @Test func tokenIsSendable() {
        let token = ProbeToken()
        // Verifying the type is Sendable at compile time:
        let _: any Sendable = token
        #expect(token.t0 == 0)
    }
}
