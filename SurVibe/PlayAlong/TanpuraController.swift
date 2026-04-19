import Foundation
import Observation
import SVAudio
import SVCore
import SwiftUI
import os.log

/// Owns tanpura drone state and debounces retune/volume changes against the
/// engine. Effective playback gate: `isSoundEnabled && isTanpuraEnabled`.
///
/// State model — two independent dimensions:
/// - `saGridHz`: a grid-aligned (whole-semitone) frequency. Updated via
///   `setSa(pitchClass:octave:)`. Always decomposable back to (pitchClass, octave).
/// - `saCentsOffset`: a small microtonal deviation in cents, clamped to ±50.
///
/// Effective audio frequency (passed to `TanpuraEngine`) is
/// `effectiveSaHz = saGridHz * 2^(saCentsOffset / 1200)`.
///
/// Retune debounce: 200 ms. Multiple rapid setters collapse into one
/// engine update with the latest effective Hz + volume.
///
/// L3 Sound-gating: `isTanpuraEnabled` represents user intent and is preserved
/// across `isSoundEnabled` flips. Only the effective engine state (driven by
/// `effectiveIsPlaying`) changes when Sound is muted.
@Observable
@MainActor
final class TanpuraController {
    // MARK: - State

    /// User intent to play tanpura. Preserved across `isSoundEnabled` flips.
    private(set) var isTanpuraEnabled: Bool = false

    /// Grid-aligned Sa frequency in Hz (whole semitone). Default = C4.
    private(set) var saGridHz: Double = 261.6255653005986

    /// Cents offset applied on top of `saGridHz`. Clamped to [-50, 50].
    private(set) var saCentsOffset: Int = 0

    /// Tanpura volume, 0.0–1.0. Default 0.3 (matches TanpuraEngine default).
    private(set) var volume: Float = 0.3

    /// Whether the Sound master toggle is currently on.
    private(set) var isSoundEnabled: Bool = true

    /// Effective audio frequency = `saGridHz * 2^(saCentsOffset / 1200)`.
    var effectiveSaHz: Double {
        saGridHz * pow(2.0, Double(saCentsOffset) / 1200.0)
    }

    /// Pitch class 0…11 (C..B) derived from `saGridHz`. Always well-defined
    /// because the grid is semitone-aligned.
    var saPitchClass: Int {
        let semitones = Int(round(12 * log2(saGridHz / Self.c4Hz)))
        return ((semitones % 12) + 12) % 12
    }

    /// Octave 3…5 derived from `saGridHz`.
    var saOctave: Int {
        let semitones = Int(round(12 * log2(saGridHz / Self.c4Hz)))
        return 4 + Int(floor(Double(semitones) / 12.0))
    }

    /// True when the engine should currently be producing sound.
    var effectiveIsPlaying: Bool { isSoundEnabled && isTanpuraEnabled }

    // MARK: - Private

    private static let c4Hz: Double = 261.6255653005986
    private static let logger = Logger.survibe(category: "TanpuraController")
    @ObservationIgnored private let engine: TanpuraEngine = TanpuraEngine()
    @ObservationIgnored private var retuneTask: Task<Void, Never>?

    // MARK: - API

    /// Toggle the user's tanpura intent. Re-evaluates engine state immediately.
    func toggleEnabled() {
        isTanpuraEnabled.toggle()
        scheduleRetune(immediate: true)
    }

    /// Set the Sound-master flag. Preserves `isTanpuraEnabled` intent;
    /// only the effective engine state changes.
    func setSoundEnabled(_ enabled: Bool) {
        guard isSoundEnabled != enabled else { return }
        isSoundEnabled = enabled
        scheduleRetune(immediate: true)
    }

    /// Set the grid-aligned Sa via pitch class (0…11) + octave (3…5).
    func setSa(pitchClass: Int, octave: Int) {
        let pc = ((pitchClass % 12) + 12) % 12
        let oct = max(3, min(5, octave))
        let semitonesFromC4 = 12 * (oct - 4) + pc
        saGridHz = Self.c4Hz * pow(2.0, Double(semitonesFromC4) / 12.0)
        scheduleRetune(immediate: false)
    }

    /// Set the cents offset, clamped to ±50.
    func setCentsOffset(_ cents: Int) {
        saCentsOffset = max(-50, min(50, cents))
        scheduleRetune(immediate: false)
    }

    /// Set volume, clamped to 0.0–1.0.
    func setVolume(_ volume: Float) {
        self.volume = max(0.0, min(1.0, volume))
        scheduleRetune(immediate: false)
    }

    /// Seed from persisted `preferredSaHz` (nil → song default).
    /// Decomposes the effective Hz into (grid, cents). Sets state but
    /// does NOT start the engine — that happens on the next user-driven
    /// change or when `effectiveIsPlaying` becomes true.
    func seed(preferredSaHz: Double?, songDefaultHz: Double = 261.6255653005986) {
        let hz = preferredSaHz ?? songDefaultHz
        let decomposed = Self.decompose(effectiveSaHz: hz)
        let semitonesFromC4 = 12 * (decomposed.octave - 4) + decomposed.pitchClass
        saGridHz = Self.c4Hz * pow(2.0, Double(semitonesFromC4) / 12.0)
        saCentsOffset = decomposed.cents
    }

    /// Stop the engine and cancel any pending retune. Call from `onDisappear`.
    func stop() {
        retuneTask?.cancel()
        retuneTask = nil
        if engine.isPlaying { engine.stop() }
    }

    // MARK: - Decomposition helper (exposed for tests and persistence round-trip)

    /// Decomposed representation of an effective Hz: whole-semitone grid plus
    /// small cents offset.
    struct Decomposed: Equatable {
        let pitchClass: Int
        let octave: Int
        let cents: Int
    }

    /// Decompose an effective Hz into (pitchClass 0…11, octave 3…5, cents ±50).
    /// Clamps octave into [3, 5].
    static func decompose(effectiveSaHz: Double) -> Decomposed {
        let semitonesFromC4 = 12 * log2(effectiveSaHz / c4Hz)
        let gridSemitones = Int(round(semitonesFromC4))
        let centsDouble = (semitonesFromC4 - Double(gridSemitones)) * 100
        let cents = max(-50, min(50, Int(round(centsDouble))))
        let pitchClass = ((gridSemitones % 12) + 12) % 12
        let octaveOffset = Int(floor(Double(gridSemitones) / 12.0))
        let octave = max(3, min(5, 4 + octaveOffset))
        return Decomposed(pitchClass: pitchClass, octave: octave, cents: cents)
    }

    // MARK: - Debounced retune

    /// Coalesce rapid changes into one engine update 200 ms after the last change.
    /// `immediate: true` bypasses debounce for discrete actions (toggle, Sound).
    private func scheduleRetune(immediate: Bool) {
        retuneTask?.cancel()
        if immediate {
            applyRetune()
            return
        }
        retuneTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            self?.applyRetune()
        }
    }

    /// Apply current state to the shared `TanpuraEngine` using its runtime
    /// mutators (`updateSaFrequency`, `updateVolume`). If not effectively
    /// playing, stops the engine; otherwise starts or retunes it in place.
    private func applyRetune() {
        guard effectiveIsPlaying else {
            if engine.isPlaying { engine.stop() }
            return
        }
        engine.updateVolume(volume)
        do {
            if engine.isPlaying {
                // Already running: retune in place. `updateSaFrequency`
                // restarts playback internally at the new Hz.
                try engine.updateSaFrequency(effectiveSaHz)
            } else {
                // Not running: push the current Sa first (no-op if unchanged),
                // then start. `updateSaFrequency` only regenerates if already
                // playing, so calling it while stopped just updates state.
                try engine.updateSaFrequency(effectiveSaHz)
                try engine.start()
            }
        } catch {
            Self.logger.error("Tanpura retune failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
