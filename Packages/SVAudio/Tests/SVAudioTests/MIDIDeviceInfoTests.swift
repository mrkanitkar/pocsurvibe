import Testing

@testable import SVAudio

// MARK: - MIDIDeviceInfoTests

@Suite("MIDIDeviceInfo")
struct MIDIDeviceInfoTests {

    // MARK: - Default Values

    @Test("default values are correct")
    func defaultValues() {
        let info = MIDIDeviceInfo(id: 1, name: "Test")
        #expect(info.manufacturer.isEmpty)
        #expect(!info.isUSB)
        #expect(!info.isBluetooth)
        #expect(!info.supportsMIDI2)
        #expect(info.sourceCount == 1)
        #expect(info.endpointRef == 0)
    }

    @Test("name is stored correctly")
    func nameStored() {
        let info = MIDIDeviceInfo(id: 7, name: "Grand Piano 88")
        #expect(info.name == "Grand Piano 88")
    }

    // MARK: - Sendable Conformance

    @Test("Sendable conformance compiles")
    func sendableConformance() {
        let info = MIDIDeviceInfo(id: 1, name: "Test")
        let _: any Sendable = info
        #expect(info.name == "Test")
    }

    // MARK: - Identifiable

    @Test("Identifiable uses Int32 id")
    func identifiableID() {
        let info = MIDIDeviceInfo(id: -5, name: "Negative")
        #expect(info.id == -5)
    }

    @Test("Identifiable works with positive id")
    func identifiablePositiveID() {
        let info = MIDIDeviceInfo(id: Int32.max, name: "MaxID")
        #expect(info.id == Int32.max)
    }

    // MARK: - Equatable

    @Test("equality based on id only")
    func equalityByID() {
        let a = MIDIDeviceInfo(id: 1, name: "A")
        let b = MIDIDeviceInfo(id: 1, name: "B")
        let c = MIDIDeviceInfo(id: 2, name: "A")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("same id different manufacturers are equal")
    func sameIDAnyManufacturerIsEqual() {
        let a = MIDIDeviceInfo(id: 10, name: "Keyboard", manufacturer: "Yamaha")
        let b = MIDIDeviceInfo(id: 10, name: "Keyboard", manufacturer: "Roland")
        #expect(a == b)
    }

    // MARK: - Hashable

    @Test("hashing based on id only")
    func hashingByID() {
        let a = MIDIDeviceInfo(id: 42, name: "KeyA")
        let b = MIDIDeviceInfo(id: 42, name: "KeyB")
        var set: Set<MIDIDeviceInfo> = [a]
        set.insert(b)
        #expect(set.count == 1)
    }

    @Test("different ids produce separate set entries")
    func differentIDsDistinctInSet() {
        let a = MIDIDeviceInfo(id: 1, name: "A")
        let b = MIDIDeviceInfo(id: 2, name: "A")
        let set: Set<MIDIDeviceInfo> = [a, b]
        #expect(set.count == 2)
    }

    // MARK: - USB Device Properties

    @Test("USB device properties")
    func usbDevice() {
        let info = MIDIDeviceInfo(
            id: 100, name: "USB Piano", manufacturer: "Yamaha",
            isUSB: true, sourceCount: 2
        )
        #expect(info.isUSB)
        #expect(!info.isBluetooth)
        #expect(info.sourceCount == 2)
        #expect(info.manufacturer == "Yamaha")
    }

    @Test("Bluetooth device properties")
    func bluetoothDevice() {
        let info = MIDIDeviceInfo(
            id: 200,
            name: "BT Keyboard",
            manufacturer: "Roland",
            isBluetooth: true
        )
        #expect(!info.isUSB)
        #expect(info.isBluetooth)
    }

    @Test("MIDI 2.0 support flag")
    func midi2Support() {
        let legacy = MIDIDeviceInfo(id: 1, name: "Old", supportsMIDI2: false)
        let modern = MIDIDeviceInfo(id: 2, name: "New", supportsMIDI2: true)
        #expect(!legacy.supportsMIDI2)
        #expect(modern.supportsMIDI2)
    }

    @Test("endpointRef stores correctly")
    func endpointRefStored() {
        let info = MIDIDeviceInfo(id: 1, endpointRef: 9999, name: "Test")
        #expect(info.endpointRef == 9999)
    }
}
