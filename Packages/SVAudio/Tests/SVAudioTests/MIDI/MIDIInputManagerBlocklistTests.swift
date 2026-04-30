import CoreMIDI
import Testing

@testable import SVAudio

// MARK: - MIDIInputManagerBlocklistTests

/// Tests for the Bluetooth-endpoint blocklist + Practice-mode dispatch added
/// in Wave 2 / Task B2 (spec §D5, §7).
///
/// These tests exercise the `updateEndpoint(_:descriptor:)` /
/// `shouldDropEvent(fromEndpointID:)` API on the `MIDIInputManager` singleton.
/// They neither start nor stop CoreMIDI; the `start()`/`stop()` lifecycle is
/// covered by `MIDIInputManagerTests`.
@Suite("MIDIInputManager Bluetooth blocklist")
struct MIDIInputManagerBlocklistTests {

    // MARK: - Helpers

    /// Reset the singleton's blocklist + Practice-mode callback between tests.
    ///
    /// The manager is a singleton; tests must clean up shared state to avoid
    /// order-dependent failures.
    private func reset(_ manager: MIDIInputManager) {
        manager.onPracticeModeRequired = nil
        manager.state.withLock { $0.blockedEndpointIDs.removeAll() }
    }

    // MARK: - Tests

    @Test("unknown endpoint is not dropped from scoring")
    func unknownEndpointNotDropped() {
        let manager = MIDIInputManager.shared
        reset(manager)

        let descriptor = EndpointDescriptor(
            endpointID: 1001,
            displayName: "Unknown",
            kind: .unknown
        )
        manager.updateEndpoint(0, descriptor: descriptor)

        #expect(!manager.shouldDropEvent(fromEndpointID: 1001))
    }

    @Test("USB endpoint is not dropped from scoring")
    func usbEndpointNotDropped() {
        let manager = MIDIInputManager.shared
        reset(manager)

        let descriptor = EndpointDescriptor(
            endpointID: 1002,
            displayName: "Yamaha PSR-400",
            kind: .usb
        )
        manager.updateEndpoint(0, descriptor: descriptor)

        #expect(!manager.shouldDropEvent(fromEndpointID: 1002))
    }

    @Test("Bluetooth endpoint is added to the scoring blocklist")
    func bluetoothEndpointDropped() {
        let manager = MIDIInputManager.shared
        reset(manager)

        let descriptor = EndpointDescriptor(
            endpointID: 1003,
            displayName: "BLE Keyboard",
            kind: .bluetooth
        )
        manager.updateEndpoint(0, descriptor: descriptor)

        #expect(manager.shouldDropEvent(fromEndpointID: 1003))
    }

    @Test("re-classifying a Bluetooth endpoint as USB removes it from the blocklist")
    func reclassifyRemovesFromBlocklist() {
        let manager = MIDIInputManager.shared
        reset(manager)

        let endpointID: MIDIUniqueID = 1004
        let bt = EndpointDescriptor(
            endpointID: endpointID,
            displayName: "BLE/USB Hybrid",
            kind: .bluetooth
        )
        manager.updateEndpoint(0, descriptor: bt)
        #expect(manager.shouldDropEvent(fromEndpointID: endpointID))

        let usb = EndpointDescriptor(
            endpointID: endpointID,
            displayName: "BLE/USB Hybrid",
            kind: .usb
        )
        manager.updateEndpoint(0, descriptor: usb)
        #expect(!manager.shouldDropEvent(fromEndpointID: endpointID))
    }

    @Test("onPracticeModeRequired fires when a Bluetooth endpoint is registered")
    func practiceModeCallbackFires() async {
        let manager = MIDIInputManager.shared
        reset(manager)

        let received = ReceivedDescriptor()
        manager.onPracticeModeRequired = { desc in
            Task { await received.set(desc) }
        }

        let descriptor = EndpointDescriptor(
            endpointID: 1005,
            displayName: "BLE Keyboard",
            kind: .bluetooth
        )
        manager.updateEndpoint(0, descriptor: descriptor)

        // The callback is dispatched via `Task { @MainActor in ... }` and the
        // capture forwards to another `Task` for actor isolation, so two yields
        // are needed before the value is observable.
        for _ in 0..<10 {
            if await received.get() != nil { break }
            await Task.yield()
        }

        let captured = await received.get()
        #expect(captured == descriptor)

        reset(manager)
    }

    @Test("onPracticeModeRequired does not fire for non-Bluetooth endpoints")
    func practiceModeCallbackSilentForUSB() async {
        let manager = MIDIInputManager.shared
        reset(manager)

        let received = ReceivedDescriptor()
        manager.onPracticeModeRequired = { desc in
            Task { await received.set(desc) }
        }

        let descriptor = EndpointDescriptor(
            endpointID: 1006,
            displayName: "USB Keyboard",
            kind: .usb
        )
        manager.updateEndpoint(0, descriptor: descriptor)

        // Give any spurious dispatch a chance to land.
        for _ in 0..<5 { await Task.yield() }

        let captured = await received.get()
        #expect(captured == nil)

        reset(manager)
    }

    @Test("registering the same Bluetooth endpoint twice fires the callback only once")
    func practiceModeCallbackIdempotent() async {
        let manager = MIDIInputManager.shared
        reset(manager)

        let count = CallbackCount()
        manager.onPracticeModeRequired = { _ in
            Task { await count.increment() }
        }

        let descriptor = EndpointDescriptor(
            endpointID: 1007,
            displayName: "BLE Keyboard",
            kind: .bluetooth
        )
        manager.updateEndpoint(0, descriptor: descriptor)
        manager.updateEndpoint(0, descriptor: descriptor)

        for _ in 0..<10 {
            if await count.value() > 0 { break }
            await Task.yield()
        }
        // Allow any second dispatch to land.
        for _ in 0..<5 { await Task.yield() }

        #expect(await count.value() == 1)

        reset(manager)
    }
}

// MARK: - Test actors

/// Actor-isolated holder for a single captured `EndpointDescriptor`.
private actor ReceivedDescriptor {
    private var descriptor: EndpointDescriptor?

    func set(_ value: EndpointDescriptor) { descriptor = value }
    func get() -> EndpointDescriptor? { descriptor }
}

/// Actor-isolated counter used to verify callback-fire counts.
private actor CallbackCount {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}
