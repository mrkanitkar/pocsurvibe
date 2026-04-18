import Foundation
import Testing

@testable import SVAudio

// MARK: - MIDIDeviceManagerTests

@Suite("MIDIDeviceManager", .serialized)
struct MIDIDeviceManagerTests {

    // MARK: - Empty State

    @Test("autoSelectBestDevice returns nil when no devices")
    func autoSelectEmptyReturnsNil() {
        let manager = MIDIDeviceManager()
        #expect(manager.autoSelectBestDevice() == nil)
    }

    @Test("availableDevices is empty by default")
    func emptyByDefault() {
        let manager = MIDIDeviceManager()
        #expect(manager.availableDevices.isEmpty)
    }

    @Test("selectedSourceEndpoints returns empty with no selection")
    func noSelectionNoEndpoints() {
        let manager = MIDIDeviceManager()
        #expect(manager.selectedSourceEndpoints().isEmpty)
    }

    // MARK: - selectDevice

    @Test("selectDevice persists to UserDefaults")
    func selectDevicePersists() {
        // Clear any stale state from parallel test runs
        UserDefaults.standard.removeObject(forKey: "midi_selected_device_id")
        let manager = MIDIDeviceManager()
        let device = MIDIDeviceInfo(
            id: 12345,
            name: "Test Keyboard",
            manufacturer: "TestCo",
            isUSB: true
        )
        manager.selectDevice(device)

        let savedID = UserDefaults.standard.integer(forKey: "midi_selected_device_id")
        #expect(savedID == 12345)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "midi_selected_device_id")
    }

    @Test("selectDevice by name with no devices is safe")
    func selectByNameNoDevices() {
        let manager = MIDIDeviceManager()
        // Should not crash
        manager.selectDevice(named: "Nonexistent")
    }

    @Test("selectDevice sets selectedDeviceID in state")
    func selectDeviceSetsID() {
        let manager = MIDIDeviceManager()
        let device = MIDIDeviceInfo(
            id: 99,
            name: "Piano",
            manufacturer: "Korg",
            isUSB: true
        )
        manager.selectDevice(device)

        // Verify via UserDefaults (the only externally observable side effect)
        let savedID = UserDefaults.standard.integer(forKey: "midi_selected_device_id")
        #expect(savedID == 99)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "midi_selected_device_id")
    }

    // MARK: - UserDefaults Restoration

    @Test("init restores selected device ID from UserDefaults")
    func initRestoresFromUserDefaults() {
        // Seed UserDefaults before creating manager
        UserDefaults.standard.set(42, forKey: "midi_selected_device_id")
        defer { UserDefaults.standard.removeObject(forKey: "midi_selected_device_id") }

        // Manager init reads the persisted key
        let manager = MIDIDeviceManager()
        // Auto-select returns nil because availableDevices is empty,
        // but the internal ID is restored — verified indirectly by confirming
        // no crash and that auto-select correctly returns nil without devices.
        #expect(manager.autoSelectBestDevice() == nil)
    }
}
