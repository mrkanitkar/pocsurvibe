import Foundation
import Testing

@testable import SVAudio

@Suite("FluidSynthMIDIEventRing")
struct FluidSynthMIDIEventRingTests {

    @Test("Empty ring yields nil from drain")
    func drainEmpty() {
        let ring = FluidSynthMIDIEventRing(capacity: 16)
        #expect(ring.dequeue() == nil)
    }

    @Test("Enqueue then dequeue yields the same event")
    func roundTripOne() {
        let ring = FluidSynthMIDIEventRing(capacity: 16)
        let evt = RealtimeMIDIEvent(timestamp: 1, channel: 0, status: 0x90, data1: 60, data2: 100)
        #expect(ring.enqueue(evt) == true)
        #expect(ring.dequeue() == evt)
        #expect(ring.dequeue() == nil)
    }

    @Test("FIFO order preserved across many events")
    func fifoOrder() {
        let ring = FluidSynthMIDIEventRing(capacity: 16)
        for i in 0..<8 {
            let evt = RealtimeMIDIEvent(
                timestamp: UInt64(i), channel: 0,
                status: 0x90, data1: UInt8(60 + i), data2: 100
            )
            #expect(ring.enqueue(evt) == true)
        }
        for i in 0..<8 {
            let evt = ring.dequeue()
            #expect(evt?.data1 == UInt8(60 + i))
        }
        #expect(ring.dequeue() == nil)
    }

    @Test("Enqueue returns false when ring is full")
    func enqueueWhenFull() {
        let ring = FluidSynthMIDIEventRing(capacity: 4)
        let evt = RealtimeMIDIEvent(timestamp: 0, channel: 0, status: 0x90, data1: 60, data2: 100)
        // Capacity 4 → ring stores at most capacity-1 = 3 events
        #expect(ring.enqueue(evt) == true)
        #expect(ring.enqueue(evt) == true)
        #expect(ring.enqueue(evt) == true)
        #expect(ring.enqueue(evt) == false)  // full
    }
}
