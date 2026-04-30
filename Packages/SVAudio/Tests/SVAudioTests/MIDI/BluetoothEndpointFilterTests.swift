import Testing

@testable import SVAudio

// MARK: - BluetoothEndpointFilterTests

/// Tests for the pure-string `parseKind(driverOwner:)` heuristic.
///
/// `detectKind(_:)` is not unit-tested here — it requires a live
/// `MIDIEndpointRef` and is exercised by integration tests on device.
@Suite("BluetoothEndpointFilter")
struct BluetoothEndpointFilterTests {

    // MARK: - Bluetooth detection

    @Test("Apple BTLE MIDI driver is detected as bluetooth")
    func appleBTLEDriverDetected() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "Apple BTLE MIDI Driver")
        #expect(kind == .bluetooth)
    }

    @Test("driver string containing 'btmidi' is detected as bluetooth")
    func btmidiSubstringDetected() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "Vendor BTMIDI Bridge")
        #expect(kind == .bluetooth)
    }

    @Test("matching is case-insensitive")
    func caseInsensitiveMatch() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "APPLE BLUETOOTH MIDI")
        #expect(kind == .bluetooth)
    }

    // MARK: - Other transports

    @Test("USB driver is detected as USB")
    func usbDriverDetected() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "USB-MIDI Driver")
        #expect(kind == .usb)
    }

    @Test("CoreMIDI Network Driver is detected as network")
    func networkDriverDetected() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "CoreMIDI Network Driver")
        #expect(kind == .network)
    }

    @Test("virtual driver is detected as virtual")
    func virtualDriverDetected() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "Some virtual driver")
        #expect(kind == .virtual)
    }

    // MARK: - Unknown / edge cases

    @Test("unrecognized driver owner returns unknown")
    func unrecognizedDriverOwner() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "xyz")
        #expect(kind == .unknown)
    }

    @Test("empty driver-owner string returns unknown")
    func emptyDriverOwner() {
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "")
        #expect(kind == .unknown)
    }

    // MARK: - Precedence

    @Test("bluetooth wins when both bluetooth and USB tokens are present")
    func bluetoothBeatsUSB() {
        // Some adapters expose themselves as e.g. "USB Bluetooth MIDI Bridge".
        // Bluetooth classification must win — otherwise scoring proceeds on a
        // BLE-jittered stream.
        let kind = BluetoothEndpointFilter.parseKind(driverOwner: "USB Bluetooth MIDI Bridge")
        #expect(kind == .bluetooth)
    }
}
