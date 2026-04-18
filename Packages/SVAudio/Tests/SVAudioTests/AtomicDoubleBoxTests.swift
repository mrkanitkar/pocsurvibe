import Testing

@testable import SVAudio

struct AtomicDoubleBoxTests {
    @Test("store then load returns stored value")
    func storeThenLoad() {
        let box = AtomicDoubleBox(initial: 0.0)
        box.store(44100.0)
        #expect(box.load() == 44100.0)
    }

    @Test("initial value is preserved before first store")
    func initialValue() {
        let box = AtomicDoubleBox(initial: 48000.0)
        #expect(box.load() == 48000.0)
    }

    @Test("latest store wins")
    func latestStoreWins() {
        let box = AtomicDoubleBox(initial: 0)
        box.store(44100)
        box.store(48000)
        box.store(22050)
        #expect(box.load() == 22050)
    }
}
