// Packages/SVAudio/Tests/SVAudioTests/Playback/MultiChannelEngineSlotTests.swift
import Foundation
import Testing

@testable import SVAudio

/// Tests for the additive slot-dispatch API on `MultiChannelEngineProtocol`.
///
/// The slot API (Task 12) lets Play Tab v2 take playback drive `samplers[2]`
/// directly without going through `AVAudioSequencer`. Two things must hold:
///
/// 1. The four new methods exist on the protocol with default no-op
///    implementations — so existing test doubles compile unchanged.
/// 2. The concrete `ProductionMultiChannelEngine` overrides those defaults
///    and routes calls into the underlying `samplers[slot]`.
///
/// Live audio output via the production engine is exercised by the broader
/// engine smoke tests; here we verify the public API surface only.
@Suite("MultiChannelEngine slot API", .serialized)
@MainActor
struct MultiChannelEngineSlotTests {

    @Test("Default protocol extension methods are no-ops on a minimal conformer")
    func defaultExtensionIsNoop() {
        let stub = StubMultiChannelEngine()
        // None of these should crash on the default no-op impls.
        stub.playNoteOnSlot(2, midi: 60, velocity: 100, channel: 0)
        stub.stopNoteOnSlot(2, midi: 60, channel: 0)
        stub.allNotesOffOnSlot(2)
        stub.sendControlChangeOnSlot(2, controller: 64, value: 100, channel: 0)
    }

    @Test("Slot API dispatches uniformly through the protocol witness table")
    func slotAPIDispatchesUniformly() {
        // Compile-time check: invoking the four new methods on `some
        // MultiChannelEngineProtocol` resolves through the witness table.
        // If a refactor removes a method or changes a signature this fails
        // to compile; if it does compile, the runtime call must be a no-op
        // for the stub conformer (default extension).
        let stub: any MultiChannelEngineProtocol = StubMultiChannelEngine()
        invokeSlotAPI(stub)
    }

    /// Drives the four slot-dispatch methods through any conformer.
    private func invokeSlotAPI(_ engine: any MultiChannelEngineProtocol) {
        engine.playNoteOnSlot(2, midi: 60, velocity: 100, channel: 0)
        engine.stopNoteOnSlot(2, midi: 60, channel: 0)
        engine.allNotesOffOnSlot(2)
        engine.sendControlChangeOnSlot(2, controller: 64, value: 100, channel: 0)
    }

    @Test("ProductionMultiChannelEngine declares the slot API surface")
    func productionEngineExposesSlotAPI() {
        // Compile-time check only: this references the four method symbols
        // on `ProductionMultiChannelEngine` so the test suite fails to build
        // if any are removed. We never invoke them — engine construction
        // requires bundled SoundFont assets that aren't available in the
        // SPM test environment.
        let _: (Int, UInt8, UInt8, UInt8) -> Void = { _, _, _, _ in }
        let _: (ProductionMultiChannelEngine) -> (Int, UInt8, UInt8, UInt8) -> Void = { engine in
            { engine.playNoteOnSlot($0, midi: $1, velocity: $2, channel: $3) }
        }
        let _: (ProductionMultiChannelEngine) -> (Int, UInt8, UInt8) -> Void = { engine in
            { engine.stopNoteOnSlot($0, midi: $1, channel: $2) }
        }
        let _: (ProductionMultiChannelEngine) -> (Int) -> Void = { engine in
            { engine.allNotesOffOnSlot($0) }
        }
        let _: (ProductionMultiChannelEngine) -> (Int, UInt8, UInt8, UInt8) -> Void = { engine in
            { engine.sendControlChangeOnSlot($0, controller: $1, value: $2, channel: $3) }
        }
        #expect(Bool(true))
    }
}

/// Minimal conformer used to verify the protocol's default no-op extension
/// keeps existing test doubles compiling without modification.
@MainActor
private final class StubMultiChannelEngine: MultiChannelEngineProtocol {
    func playTouchNote(_ midiNote: UInt8, velocity: UInt8) {}
    func stopTouchNote(_ midiNote: UInt8) {}
    func stopAllTouchNotes() {}
    func loadSong(source: MIDISource) async throws {}
    func unloadSong() {}
    var currentSong: SongHandle? { nil }
    func play() throws {}
    func pause() {}
    func stop() {}
    var isPlaying: Bool { false }
    var currentPositionInSeconds: TimeInterval { 0 }
    func setRate(_ rate: Float) {}
    var rate: Float { 1.0 }
    func flushSongPrograms() {}
}
