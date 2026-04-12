import Foundation
import Testing

@testable import SurVibe

/// Tests for VisualizationMode, KeyboardLayoutMode, and AudioNodeAdapter.
@MainActor
struct AudioVisualizationTests {

    // MARK: - VisualizationMode

    @Test @MainActor func visualizationModeRawValues() {
        #expect(VisualizationMode.tuner.rawValue == "tuner")
        #expect(VisualizationMode.waveform.rawValue == "waveform")
        #expect(VisualizationMode.pitchTrack.rawValue == "pitchTrack")
        #expect(VisualizationMode.spectrum.rawValue == "spectrum")
    }

    @Test func allModesHaveDisplayNames() {
        for mode in VisualizationMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode) should have a display name")
        }
    }

    @Test func allModesHaveIcons() {
        for mode in VisualizationMode.allCases {
            #expect(!mode.systemImage.isEmpty, "\(mode) should have a system image")
        }
    }

    @Test func visualizationModeHasFourCases() {
        #expect(VisualizationMode.allCases.count == 4)
    }

    @Test func visualizationModeRoundTripsFromRawValue() {
        for mode in VisualizationMode.allCases {
            let roundTripped = VisualizationMode(rawValue: mode.rawValue)
            #expect(roundTripped == mode, "\(mode) should round-trip from rawValue")
        }
    }

    // MARK: - KeyboardLayoutMode

    @Test func keyboardLayoutModeValues() {
        #expect(KeyboardLayoutMode.piano.rawValue == "piano")
        #expect(KeyboardLayoutMode.isomorphic.rawValue == "isomorphic")
    }

    @Test func keyboardLayoutModeHasTwoCases() {
        #expect(KeyboardLayoutMode.allCases.count == 2)
    }

    @Test func keyboardLayoutModeDisplayNames() {
        #expect(KeyboardLayoutMode.piano.displayName == "Piano")
        #expect(KeyboardLayoutMode.isomorphic.displayName == "Sargam")
    }

    @Test func keyboardLayoutModeIcons() {
        #expect(KeyboardLayoutMode.piano.systemImage == "pianokeys")
        #expect(KeyboardLayoutMode.isomorphic.systemImage == "rectangle.grid.1x2")
    }

    // MARK: - AudioNodeAdapter

    @Test @MainActor func audioNodeAdapterConnectionRequiresRunningEngine() {
        // AudioNodeAdapter.connect() should throw when engine is not running
        let adapter = AudioNodeAdapter.shared
        #expect(!adapter.isConnected, "Adapter should start disconnected")
    }

    @Test @MainActor func audioNodeAdapterDisconnectIsIdempotent() {
        let adapter = AudioNodeAdapter.shared
        // Disconnecting when not connected should be safe
        adapter.disconnect()
        #expect(!adapter.isConnected, "Adapter should still be disconnected")
        adapter.disconnect()
        #expect(!adapter.isConnected, "Multiple disconnects should be safe")
    }

    @Test @MainActor func audioNodeAdapterErrorDescription() {
        let error = AudioNodeAdapterError.engineNotRunning
        #expect(!error.localizedDescription.isEmpty, "Error should have a description")
    }
}
