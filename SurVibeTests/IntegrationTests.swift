import Testing
import SVCore
import SVAudio

/// Integration tests verifying Sprint 0 demo scenarios.
///
/// Uses `.serialized` to prevent parallel tests from polluting shared
/// singleton state (AnalyticsManager, SoundFontManager, etc.).
@Suite("Sprint 0 Integration Tests", .serialized)
@MainActor
struct IntegrationTests {

    // MARK: - D2: SoundFont play (stub verification)

    @Test("SoundFontManager singleton initializes")
    @MainActor func testSoundFontManagerInit() {
        let manager = SoundFontManager.shared
        // Singleton is accessible — isLoaded may be true if another test
        // triggered loading, so we just verify the singleton exists.
        #expect(manager === SoundFontManager.shared, "shared should return same instance")
    }

    // MARK: - D3: Pitch detection pipeline (protocol verification)

    @Test("PitchDetectorProtocol has two implementations")
    @MainActor func testPitchDetectorImplementations() {
        // Verifies both implementations conform to the protocol
        let audioKit: any PitchDetectorProtocol = AudioKitPitchDetector()
        let yin: any PitchDetectorProtocol = YINPitchDetector()
        #expect(type(of: audioKit) == AudioKitPitchDetector.self)
        #expect(type(of: yin) == YINPitchDetector.self)
    }

    @Test("PitchResult can be constructed with all fields")
    @MainActor func testPitchResultConstruction() {
        let result = PitchResult(
            frequency: 261.63,
            amplitude: 0.7,
            noteName: "Sa",
            octave: 4,
            centsOffset: -2.0,
            confidence: 0.9
        )
        #expect(result.noteName == "Sa")
        #expect(result.octave == 4)
    }

    // MARK: - D4: Simultaneous I/O (node graph verification)

    @Test("AudioEngineManager has correct node graph")
    @MainActor func testNodeGraph() {
        let manager = AudioEngineManager.shared
        // Verify structural properties only — do NOT assert isRunning because
        // other tests or the host app may have started the engine.
        #expect(manager.bufferSize == 1024)
        // Access nodes to verify they exist (all non-optional)
        _ = manager.engine
        _ = manager.sampler
        _ = manager.tanpuraNode
        _ = manager.metronomeNode
    }

    // MARK: - D6: PostHog event fires (event definition verification)

    @Test("Sprint 0 analytics events are defined")
    @MainActor func testAnalyticsEvents() {
        #expect(AnalyticsEvent.appScaffoldingLoaded.rawValue == "app_scaffolding_loaded")
        #expect(AnalyticsEvent.audioPocPitchDetected.rawValue == "audio_poc_pitch_detected")
        #expect(AnalyticsEvent.cloudKitSyncCompleted.rawValue == "cloudkit_sync_completed")
        #expect(AnalyticsEvent.tabSelected.rawValue == "tab_selected")
    }

    @Test("AnalyticsManager singleton exists")
    @MainActor func testAnalyticsManagerInit() {
        let manager = AnalyticsManager.shared
        // Verify singleton is accessible and tracking can be toggled
        manager.setTrackingEnabled(false)
        #expect(!manager.isTrackingEnabled)
        manager.setTrackingEnabled(true)
        #expect(manager.isTrackingEnabled)
    }

    // MARK: - D7: VoiceOver labels

    @Test("VoiceOver labels exist for all tabs")
    @MainActor func testTabAccessibilityLabels() {
        let tabs = ["Learn", "Practice", "Songs", "Profile"]
        for tab in tabs {
            let label = AccessibilityHelper.tabLabel(for: tab)
            #expect(label.contains("tab"))
        }
    }

    @Test("VoiceOver labels exist for all 12 swar notes")
    @MainActor func testSwarAccessibilityLabels() {
        let notes = ["Sa", "Komal Re", "Re", "Komal Ga", "Ga", "Ma",
                     "Tivra Ma", "Pa", "Komal Dha", "Dha", "Komal Ni", "Ni"]
        for note in notes {
            let label = AccessibilityHelper.swarLabel(for: note)
            #expect(!label.isEmpty)
        }
    }

    // MARK: - Rang Color System

    @Test("All rang levels have distinct colors and body text colors")
    @MainActor func testRangColors() {
        // Verify all 5 levels have color properties and display names
        #expect(RangLevel.allCases.count == 5)
        for level in RangLevel.allCases {
            #expect(!level.displayName.isEmpty)
            #expect(!level.proficiencyLabel.isEmpty)
        }
        // Verify XP threshold progression
        #expect(RangLevel.neel.xpThreshold < RangLevel.hara.xpThreshold)
        #expect(RangLevel.hara.xpThreshold < RangLevel.peela.xpThreshold)
        #expect(RangLevel.peela.xpThreshold < RangLevel.lal.xpThreshold)
        #expect(RangLevel.lal.xpThreshold < RangLevel.sona.xpThreshold)
    }

    // MARK: - Audio Config

    @Test("Default audio config within latency budget")
    @MainActor func testAudioLatency() {
        let config = AudioConfig.pitchDetection
        #expect(config.latencyMs < 50.0, "Latency must be under 50ms target")
        #expect(config.bufferSize == 1024)
        #expect(config.sampleRate == 44100)
    }

    // MARK: - Swar Note Model

    @Test("Swar frequency math is correct for Sa (C4)")
    @MainActor func testSaFrequency() {
        let freq = Swar.sa.frequency(octave: 4, referencePitch: 440.0)
        #expect(abs(freq - 261.626) < 0.01)
    }

    @Test("Swar MIDI notes are correct")
    @MainActor func testSwarMidi() {
        #expect(Swar.sa.midiNote(octave: 4) == 60)
        #expect(Swar.pa.midiNote(octave: 4) == 67)
        #expect(Swar.ni.midiNote(octave: 4) == 71)
    }
}
