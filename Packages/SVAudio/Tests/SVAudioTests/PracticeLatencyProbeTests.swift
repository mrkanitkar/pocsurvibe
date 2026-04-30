import Testing
@testable import SVAudio

struct PracticeLatencyProbeTests {

    @Test func sharedInstanceExists() {
        let probe = PracticeLatencyProbe.shared
        #expect(probe != nil)
    }

    @Test func recordCompletedTokenIncreasesCount() {
        let probe = PracticeLatencyProbe.shared
        probe.reset()

        var token = ProbeToken()
        token.stamp(.inputReceived)
        token.stamp(.dspComplete)
        token.stamp(.matchComplete)
        token.stamp(.framePresented)

        probe.record(token)
        #expect(probe.completedCount == 1)
    }

    @Test func recordIncompleteTokenIsIgnored() {
        let probe = PracticeLatencyProbe.shared
        probe.reset()

        var token = ProbeToken()
        token.stamp(.inputReceived)
        // Incomplete — missing t1, t2, t3

        probe.record(token)
        #expect(probe.completedCount == 0)
    }

    @Test func resetClearsCount() {
        let probe = PracticeLatencyProbe.shared
        probe.reset()

        var token = ProbeToken()
        token.stamp(.inputReceived)
        token.stamp(.dspComplete)
        token.stamp(.matchComplete)
        token.stamp(.framePresented)

        probe.record(token)
        #expect(probe.completedCount == 1)

        probe.reset()
        #expect(probe.completedCount == 0)
    }
}
