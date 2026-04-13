import Testing

@testable import SVAudio

struct FrameDropCounterTests {

    // MARK: - Initial State

    @Test
    func initialCountIsZero() {
        let counter = FrameDropCounter()
        let drops = counter.count
        #expect(drops == 0)
    }

    // MARK: - Normal Frames (No Drop)

    @Test
    func normalFrameDoesNotIncrement() {
        let counter = FrameDropCounter()
        // 120 Hz: expected interval ~8.33 ms
        // Normal frame: target - timestamp = one interval (~8.33 ms)
        let timestamp = 1000.0
        let targetTimestamp = timestamp + (1.0 / 120.0)
        counter.recordFrame(timestamp: timestamp, targetTimestamp: targetTimestamp)
        let drops = counter.count
        #expect(drops == 0)
    }

    @Test
    func frameJustBelowThresholdDoesNotIncrement() {
        let counter = FrameDropCounter()
        let interval = 1.0 / 120.0
        // Delta just under threshold should NOT count
        let timestamp = 1000.0
        let targetTimestamp = timestamp + interval * 1.5 - 0.0001
        counter.recordFrame(timestamp: timestamp, targetTimestamp: targetTimestamp)
        let drops = counter.count
        #expect(drops == 0)
    }

    // MARK: - Dropped Frames

    @Test
    func droppedFrameIncrements() {
        let counter = FrameDropCounter()
        let interval = 1.0 / 120.0
        // Delta just over 1.5x interval signals a drop
        let timestamp = 1000.0
        let targetTimestamp = timestamp + interval * 1.5 + 0.001
        counter.recordFrame(timestamp: timestamp, targetTimestamp: targetTimestamp)
        #expect(counter.count == 1)
    }

    @Test
    func twoDroppedFramesIncrements() {
        let counter = FrameDropCounter()
        let interval = 1.0 / 120.0
        let largeGap = interval * 2.0  // clearly exceeds 1.5x

        counter.recordFrame(timestamp: 1000.0, targetTimestamp: 1000.0 + largeGap)
        counter.recordFrame(timestamp: 1000.0 + largeGap, targetTimestamp: 1000.0 + largeGap * 2.0)
        #expect(counter.count == 2)
    }

    @Test
    func consecutiveDropsCountCorrectly() {
        let counter = FrameDropCounter()
        let interval = 1.0 / 120.0
        let dropped = interval * 3.0  // well over threshold
        let normal = interval  // under threshold

        // drop, normal, drop, drop
        counter.recordFrame(timestamp: 0.0, targetTimestamp: dropped)
        counter.recordFrame(timestamp: dropped, targetTimestamp: dropped + normal)
        counter.recordFrame(timestamp: dropped + normal, targetTimestamp: dropped + normal + dropped)
        counter.recordFrame(
            timestamp: dropped + normal + dropped,
            targetTimestamp: dropped + normal + dropped + dropped
        )

        #expect(counter.count == 3)
    }

    // MARK: - Reset

    @Test
    func resetClearsCount() {
        let counter = FrameDropCounter()
        let interval = 1.0 / 120.0
        let largeGap = interval * 2.0

        counter.recordFrame(timestamp: 1000.0, targetTimestamp: 1000.0 + largeGap)
        #expect(counter.count == 1)

        counter.reset()
        let drops = counter.count
        #expect(drops == 0)
    }

    // MARK: - Custom Interval

    @Test
    func customIntervalThreshold() {
        // 60 Hz: expected interval ~16.67 ms
        let interval60Hz = 1.0 / 60.0
        let counter = FrameDropCounter(expectedInterval: interval60Hz)

        // Normal 60 Hz frame — should not drop
        counter.recordFrame(timestamp: 0.0, targetTimestamp: interval60Hz)
        let dropsAfterNormal = counter.count
        #expect(dropsAfterNormal == 0)

        // Gap exceeding 1.5x of 60 Hz interval — should drop
        counter.recordFrame(timestamp: interval60Hz, targetTimestamp: interval60Hz + interval60Hz * 2.0)
        #expect(counter.count == 1)
    }

    @Test
    func customThresholdMultiplier() {
        let interval = 1.0 / 120.0
        // Stricter threshold: 1.2x instead of 1.5x
        let counter = FrameDropCounter(expectedInterval: interval, thresholdMultiplier: 1.2)

        // 1.3x interval — under default 1.5x but over custom 1.2x
        let delta = interval * 1.3
        counter.recordFrame(timestamp: 0.0, targetTimestamp: delta)
        #expect(counter.count == 1)
    }
}
