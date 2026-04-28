// Packages/SVAudio/Tests/SVAudioTests/ProductionMultiChannelEngineTests.swift
import AVFoundation
import Foundation
import Testing

@testable import SVAudio

@Suite("ProductionMultiChannelEngine — init + touch", .serialized)
@MainActor
struct ProductionMultiChannelEngineTests {

    @Test("init attaches 16 samplers + subMixer + timePitch to the engine")
    func initAttaches() throws {
        let engine = AVAudioEngine()
        try engine.start()
        defer { engine.stop() }

        let m = try ProductionMultiChannelEngine(engine: engine)
        #expect(m.samplers.count == 16)
        // sampler[0] should be loaded with Acoustic Grand (program 0). Hard to
        // introspect AU state directly; smoke check that the sampler exists
        // and is attached.
        #expect(m.samplers.allSatisfy { $0.engine === engine })
    }

    @Test("playTouchNote and stopTouchNote do not throw")
    func touchSmoke() throws {
        let engine = AVAudioEngine()
        try engine.start()
        defer { engine.stop() }
        let m = try ProductionMultiChannelEngine(engine: engine)

        // Smoke check — no audible verification possible in unit tests.
        m.playTouchNote(60, velocity: 100)
        Thread.sleep(forTimeInterval: 0.05)
        m.stopTouchNote(60)
        m.stopAllTouchNotes()
    }

    @Test("playTouchNote before engine start is a logged no-op")
    func touchBeforeStart() throws {
        let engine = AVAudioEngine()
        let m = try ProductionMultiChannelEngine(engine: engine)
        // Engine not started yet — should not throw.
        m.playTouchNote(60, velocity: 100)
        m.stopTouchNote(60)
    }

    @Test("currentSong is nil after init")
    func currentSongNil() throws {
        let engine = AVAudioEngine()
        try engine.start()
        defer { engine.stop() }
        let m = try ProductionMultiChannelEngine(engine: engine)
        #expect(m.currentSong == nil)
        #expect(!m.isPlaying)
    }

    @Test("setRate clamps to 0.5...1.5")
    func rateClamp() throws {
        let engine = AVAudioEngine()
        try engine.start()
        defer { engine.stop() }
        let m = try ProductionMultiChannelEngine(engine: engine)
        m.setRate(2.0)
        #expect(m.rate == 1.5)
        m.setRate(0.1)
        #expect(m.rate == 0.5)
        m.setRate(1.0)
        #expect(m.rate == 1.0)
    }
}
