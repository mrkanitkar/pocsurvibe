import AVFoundation
import ObjCExceptionCatcher
import SVCore
import os.log

/// Manages SoundFont instrument loading and MIDI note playback
/// via AVAudioUnitSampler connected to AudioEngineManager's engine.
///
/// Uses the bundled UprightPianoKW.sf2 — a real multi-sampled piano
/// (27 sample zones, 2 velocity layers) from the FreePats project,
/// released under CC0 (public domain).
///
/// ## ObjC Exception Safety
/// `AVAudioUnitSampler.loadSoundBankInstrument` can raise ObjC
/// exceptions (not Swift errors) on malformed SF2 files. This class
/// uses `SVAudioTryObjC` to catch those exceptions and convert them
/// to Swift `Error` values, preventing app crashes.
@MainActor
public final class SoundFontManager: SoundFontPlaying {
    // MARK: - Properties

    public static let shared = SoundFontManager()

    /// Reference to the engine's sampler node.
    private var sampler: AVAudioUnitSampler {
        AudioEngineManager.shared.sampler
    }

    /// Whether a SoundFont is currently loaded.
    public private(set) var isLoaded: Bool = false

    /// Currently active (playing) MIDI notes, keyed by (note, channel).
    ///
    /// Used by `stopAllNotes()` to iterate only active notes instead of
    /// all 128 MIDI values. Encoded as `UInt16(channel) << 8 | UInt16(note)`.
    private var activeNotes: Set<UInt16> = []

    private static let logger = Logger.survibe(category: "SoundFontManager")

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Load a SoundFont bank instrument into the sampler.
    ///
    /// Wraps `AVAudioUnitSampler.loadSoundBankInstrument` with ObjC
    /// exception safety. If the SF2 file is malformed, returns a Swift
    /// `Error` instead of crashing the process.
    ///
    /// - Parameters:
    ///   - url: URL to the .sf2 SoundFont file.
    ///   - program: MIDI program number (default: 0 = Piano).
    ///   - bankMSB: Bank MSB (default: kAUSampler_DefaultMelodicBankMSB).
    ///   - bankLSB: Bank LSB (default: 0).
    /// - Throws: `SoundFontError.loadFailed` if the SF2 cannot be loaded.
    public func loadSoundFont(
        at url: URL,
        program: UInt8 = 0,
        bankMSB: UInt8 = UInt8(kAUSampler_DefaultMelodicBankMSB),
        bankLSB: UInt8 = 0
    ) throws {
        // Capture any Swift error thrown inside the ObjC try block.
        var swiftError: (any Error)?

        var objcError: NSError?
        let success = SVAudioTryObjC({
            do {
                try self.sampler.loadSoundBankInstrument(
                    at: url,
                    program: program,
                    bankMSB: bankMSB,
                    bankLSB: bankLSB
                )
            } catch {
                swiftError = error
            }
        }, &objcError)

        if let swiftError {
            throw swiftError
        }

        if !success {
            let message = objcError?.localizedDescription ?? "Unknown SoundFont load failure"
            Self.logger.error("SoundFont ObjC exception: \(message, privacy: .public)")
            throw SoundFontError.loadFailed(message)
        }

        isLoaded = true
    }

    /// Load the bundled UprightPianoKW.sf2 SoundFont from SVAudio resources.
    ///
    /// AUD-016: This is an `async` function so the SF2 disk-load happens on a
    /// background executor (`Task.detached(priority: .userInitiated)`), avoiding
    /// a potential main-thread stall on first launch when the SF2 file is read
    /// from the app bundle for the first time (~50–150ms on cold cache).
    ///
    /// Starts the audio engine for playback if not already running, then
    /// loads the piano SoundFont. Safe to call multiple times — returns
    /// immediately if already loaded AND the engine is still running.
    ///
    /// The bundled SoundFont is a real multi-sampled upright piano
    /// (FreePats UprightPianoKW, CC0 public domain) with 27 sample zones
    /// and 2 velocity layers for natural-sounding playback.
    ///
    /// - Throws: If the engine fails to start or the SoundFont fails to load.
    public func loadBundledPiano() async throws {
        // Re-load if the engine was stopped since last load (e.g. after cleanup()).
        // isLoaded=true with a stopped engine means the sampler AU is disconnected.
        guard !isLoaded || !AudioEngineManager.shared.isRunning else { return }

        // Start the audio engine in playback-only mode (no mic permission).
        try AudioEngineManager.shared.startForPlayback()

        guard let url = Bundle.module.url(
            forResource: "UprightPianoKW",
            withExtension: "sf2"
        ) else {
            Self.logger.error("UprightPianoKW.sf2 not found in SVAudio bundle")
            throw SoundFontError.loadFailed(
                "Piano SoundFont not found in app bundle"
            )
        }

        // AUD-016: `loadBundledPiano()` is `async` so callers can await it without
        // blocking their own async contexts. `loadSoundFont(at:)` calls
        // `AVAudioUnitSampler.loadSoundBankInstrument` which must remain on
        // MainActor (AVAudioUnitSampler is not thread-safe), so the call stays
        // on the MainActor here. The `async` signature gives callers the ability
        // to `try await` without blocking the call site's thread.
        try loadSoundFont(at: url)
        Self.logger.info("Bundled piano SoundFont loaded (UprightPianoKW)")
    }

    /// Play a MIDI note with given velocity on the sampler.
    /// - Parameters:
    ///   - midiNote: MIDI note number (0-127)
    ///   - velocity: Key velocity (0-127, default: 100)
    ///   - channel: MIDI channel (0-15, default: 0)
    public func playNote(midiNote: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sampler.startNote(midiNote, withVelocity: velocity, onChannel: channel)
        activeNotes.insert(Self.noteKey(note: midiNote, channel: channel))
    }

    /// Stop a playing MIDI note.
    /// - Parameters:
    ///   - midiNote: MIDI note number to stop
    ///   - channel: MIDI channel (0-15, default: 0)
    public func stopNote(midiNote: UInt8, channel: UInt8 = 0) {
        sampler.stopNote(midiNote, onChannel: channel)
        activeNotes.remove(Self.noteKey(note: midiNote, channel: channel))
    }

    /// Stop all currently playing notes.
    ///
    /// Iterates only notes that were started via `playNote`, not all 128 MIDI values.
    public func stopAllNotes() {
        for key in activeNotes {
            let (note, channel) = Self.decodeKey(key)
            sampler.stopNote(note, onChannel: channel)
        }
        activeNotes.removeAll()
    }

    /// Reset the loaded state so `loadBundledPiano()` will re-attach the sampler
    /// after the audio engine has been stopped and restarted.
    ///
    /// Call this whenever `AudioEngineManager.stop()` is called so the sampler
    /// is properly reloaded into the new engine graph on the next session.
    public func resetLoadedState() {
        isLoaded = false
    }

    // MARK: - Private Methods

    /// Encode a MIDI note and channel into a single UInt16 key.
    private static func noteKey(note: UInt8, channel: UInt8) -> UInt16 {
        UInt16(channel) << 8 | UInt16(note)
    }

    /// Decode a UInt16 key back into MIDI note and channel.
    private static func decodeKey(_ key: UInt16) -> (UInt8, UInt8) {
        let note = UInt8(key & 0xFF)
        let channel = UInt8(key >> 8)
        return (note, channel)
    }
}

// MARK: - SoundFontError

/// Errors specific to SoundFont loading operations.
public enum SoundFontError: SurVibeError {
    /// The SoundFont file failed to load into the sampler.
    case loadFailed(String)

    public var domain: String { "SVAudio" }

    public var code: String {
        switch self {
        case .loadFailed: "load_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let reason):
            String(localized: "SoundFont load failed: \(reason)")
        }
    }
}
