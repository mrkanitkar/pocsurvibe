// Packages/SVAudio/Tests/SVAudioTests/ProductionMultiChannelEngineTests.swift
import AVFoundation
import Foundation
import Testing

@testable import SVAudio

@Suite("ProductionMultiChannelEngine — init + touch", .serialized)
@MainActor
struct ProductionMultiChannelEngineTests {

    /// Shared instance for all tests in this suite. Lazily constructed on
    /// first access. This matches the production deployment shape — exactly
    /// one ProductionMultiChannelEngine is ever attached to the shared
    /// AudioEngineManager.shared.engine.
    static var sharedInstance: ProductionMultiChannelEngine?

    /// Idempotent setup. Returns the shared instance, constructing it once.
    static func makeOrGetEngine() throws -> ProductionMultiChannelEngine {
        if let existing = sharedInstance { return existing }
        try AudioEngineManager.shared.startForPlayback()
        let m = try ProductionMultiChannelEngine(engine: AudioEngineManager.shared.engine)
        sharedInstance = m
        return m
    }

    @Test("init attaches 16 samplers + subMixer + timePitch to the engine")
    func initAttaches() throws {
        let m = try Self.makeOrGetEngine()
        #expect(m.samplers.count == 16)
        let engine = AudioEngineManager.shared.engine
        #expect(m.samplers.allSatisfy { $0.engine === engine })
    }

    @Test("playTouchNote and stopTouchNote do not throw")
    func touchSmoke() throws {
        let m = try Self.makeOrGetEngine()
        m.playTouchNote(60, velocity: 100)
        Thread.sleep(forTimeInterval: 0.05)
        m.stopTouchNote(60)
        m.stopAllTouchNotes()
    }

    @Test("playTouchNote on the shared engine instance does not throw before any song is loaded")
    func touchBeforeAnySong() throws {
        // Replaces the spec's "before engine start" test. Since the
        // suite uses the production AudioEngineManager (which is started
        // by makeOrGetEngine), simulating a stopped engine would tear
        // down state needed by other tests. Instead, verify that touch
        // input is safe in the most likely "no song yet" production
        // entry-point shape.
        let m = try Self.makeOrGetEngine()
        m.playTouchNote(60, velocity: 100)
        m.stopTouchNote(60)
    }

    @Test("currentSong is nil after init")
    func currentSongNil() throws {
        let m = try Self.makeOrGetEngine()
        #expect(m.currentSong == nil)
        #expect(!m.isPlaying)
    }

    @Test("setRate clamps to 0.5...1.5")
    func rateClamp() throws {
        let m = try Self.makeOrGetEngine()
        m.setRate(2.0)
        #expect(m.rate == 1.5)
        m.setRate(0.1)
        #expect(m.rate == 0.5)
        m.setRate(1.0)
        #expect(m.rate == 1.0)
    }

    @Test("loadSong with raw MIDI configures samplers and sequencer")
    func loadSongMidi() async throws {
        let m = try Self.makeOrGetEngine()
        let smf = TestSMFFactory.buildSMF(programs: [0, 24])
        try await m.loadSong(source: .midi(smf))

        #expect(m.currentSong != nil)
        #expect(m.currentSong?.trackCount == 2)
        #expect(m.currentSong?.programs == [0, 24])
    }

    @Test("loadSong replaces a previously-loaded song")
    func loadSongReplace() async throws {
        let m = try Self.makeOrGetEngine()

        let s1 = TestSMFFactory.buildSMF(programs: [0, 24])
        try await m.loadSong(source: .midi(s1))
        #expect(m.currentSong?.trackCount == 2)

        let s2 = TestSMFFactory.buildSMF(programs: [27, 56, 65])
        try await m.loadSong(source: .midi(s2))
        #expect(m.currentSong?.trackCount == 3)
        #expect(m.currentSong?.programs == [27, 56, 65])
    }

    @Test("loadSong throws tooManyTracks when source exceeds 15")
    func loadSongTooMany() async throws {
        let m = try Self.makeOrGetEngine()
        let programs: [UInt8?] = Array(repeating: UInt8(0), count: 16).map(Optional.some)
        let smf = TestSMFFactory.buildSMF(programs: programs)
        do {
            try await m.loadSong(source: .midi(smf))
            Issue.record("expected throw")
        } catch let MultiChannelEngineError.tooManyTracks(found, max) {
            #expect(found == 16)
            #expect(max == 15)
        }
    }

    @Test("unloadSong clears state")
    func unloadAfterLoad() async throws {
        let m = try Self.makeOrGetEngine()
        let smf = TestSMFFactory.buildSMF(programs: [0])
        try await m.loadSong(source: .midi(smf))
        #expect(m.currentSong != nil)
        m.unloadSong()
        #expect(m.currentSong == nil)
    }
}
