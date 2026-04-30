import Testing
@testable import SVCore

struct HostTimeTests {
    @Test func nowProducesMonotonicallyIncreasingValues() {
        let a = HostTime.now()
        let b = HostTime.now()
        #expect(b.rawTicks >= a.rawTicks)
    }

    @Test func secondsSinceConvertsTicksToSeconds() {
        let a = HostTime(rawTicks: 0)
        let b = HostTime(rawTicks: 1_000_000_000)
        let delta = b.seconds(since: a)
        #expect(delta > 0)
        #expect(delta < 100.0)
    }

    @Test func secondsSinceIsSymmetric() {
        let a = HostTime.now()
        let b = HostTime(rawTicks: a.rawTicks + 1_000_000)
        let forward = b.seconds(since: a)
        let backward = a.seconds(since: b)
        #expect(abs(forward + backward) < 0.0001)
    }

    @Test func sendableAndHashable() {
        let a = HostTime(rawTicks: 42)
        let b = HostTime(rawTicks: 42)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
