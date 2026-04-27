import AVFoundation
import FluidSynth
import Foundation
import os

private let rendererLogger = Logger.survibe(category: "FluidSynthRenderer")

/// `@unchecked Sendable` C-pointer wrapper around `fluid_synth_t*`. The
/// FluidSynth C API is documented as not fully thread-safe; we follow the
/// project's `MIDIInputManager` pattern (per `audio.md`) — exempt from the
/// `@unchecked Sendable` ban because CoreAudio realtime callbacks need
/// pointer access and the rest of the API is funnelled through a single
/// `@MainActor`-isolated owner (`FluidSynthEngine`).
///
/// The render block produced by `makeRenderBlock` runs on the CoreAudio
/// realtime thread. It drains the MIDI event ring (filled by the CoreMIDI
/// receive thread elsewhere), dispatches `fluid_synth_noteon` /
/// `fluid_synth_noteoff` / `fluid_synth_program_change`, then renders the
/// requested frame count via `fluid_synth_write_float`.
public final class FluidSynthRenderer: @unchecked Sendable {

    // MARK: - Properties

    /// `nonisolated(unsafe)` justified: written only on the @MainActor
    /// owner during init/loadSoundFont/setProgram/tearDown, and the
    /// pointer-sized read on the realtime thread is atomic on arm64.
    /// FluidSynth's `fluid_synth_noteon` etc. take an internal mutex, so
    /// concurrent writes from the realtime thread (via the render block)
    /// and the @MainActor thread (via `setProgram`) are serialised by
    /// FluidSynth itself.
    nonisolated(unsafe) private var settings: OpaquePointer?

    /// `nonisolated(unsafe)` justified: see `settings`. The synth pointer
    /// is set once at init, mutated only on `deinit`, and read from the
    /// realtime thread under FluidSynth's internal mutex.
    nonisolated(unsafe) private var synth: OpaquePointer?

    /// `nonisolated(unsafe)` justified: tracked by the @MainActor owner
    /// across `loadSoundFont` calls; never read from the realtime thread.
    nonisolated(unsafe) private var sfontID: Int32 = -1

    private let ring: FluidSynthMIDIEventRing

    // MARK: - Initialization

    /// Creates a FluidSynth renderer bound to a shared MIDI event ring.
    ///
    /// Allocates a `fluid_settings_t` and `fluid_synth_t` configured for
    /// the host audio sample rate and the requested polyphony. FluidSynth's
    /// own audio driver is disabled (`audio.driver = ""`) because output
    /// is driven via `AVAudioSourceNode` from `makeRenderBlock`.
    ///
    /// - Parameters:
    ///   - sampleRate: Host audio output sample rate in Hz (e.g. 48000).
    ///   - polyphony: Maximum simultaneous voices. Default 256.
    ///   - ring: SPSC MIDI event ring filled by the CoreMIDI receive
    ///     callback or MIDI file scheduler; drained on the audio thread.
    public init(sampleRate: Double, polyphony: Int32 = 256, ring: FluidSynthMIDIEventRing) {
        self.ring = ring
        self.settings = new_fluid_settings()
        guard let settings else {
            rendererLogger.error("init: new_fluid_settings returned nil")
            return
        }
        fluid_settings_setnum(settings, "synth.sample-rate", sampleRate)
        fluid_settings_setint(settings, "synth.polyphony", polyphony)
        // Disable FluidSynth's own audio driver — we drive it via render block
        fluid_settings_setstr(settings, "audio.driver", "")
        self.synth = new_fluid_synth(settings)
        if synth == nil {
            rendererLogger.error("init: new_fluid_synth returned nil")
        } else {
            rendererLogger.info(
                "init: sampleRate=\(sampleRate, privacy: .public) polyphony=\(polyphony, privacy: .public)"
            )
        }
    }

    deinit {
        if let synth { delete_fluid_synth(synth) }
        if let settings { delete_fluid_settings(settings) }
    }

    // MARK: - Public Methods

    /// Loads an SF2 SoundFont file. Replaces any previously-loaded font.
    ///
    /// Calls `fluid_synth_sfload` after unloading any prior font so that
    /// preset slots are reset. The returned id is the FluidSynth-internal
    /// font identifier and is also retained on the renderer for later
    /// unload.
    ///
    /// - Parameter url: File URL of the `.sf2` file. Must be readable.
    /// - Returns: FluidSynth-internal font id (>= 0).
    /// - Throws: `PipelineError.bounceFailed` if the synth is not
    ///   initialised or the C-side load returns a negative id.
    @discardableResult
    public func loadSoundFont(at url: URL) throws -> Int32 {
        guard let synth else {
            throw PipelineError.bounceFailed(reason: "FluidSynth not initialised")
        }
        // Unload previous font if any
        if sfontID >= 0 {
            fluid_synth_sfunload(synth, sfontID, 1 /*reset_presets*/)
            sfontID = -1
        }
        let id = url.path.withCString { path in
            fluid_synth_sfload(synth, path, 1 /*reset_presets*/)
        }
        if id < 0 {
            throw PipelineError.bounceFailed(
                reason: "fluid_synth_sfload failed for \(url.lastPathComponent)"
            )
        }
        sfontID = id
        rendererLogger.info(
            "loadSoundFont: \(url.lastPathComponent, privacy: .public) sfontID=\(id, privacy: .public)"
        )
        return id
    }

    /// Sets the General MIDI program (instrument patch) for a given
    /// MIDI channel.
    ///
    /// Wraps `fluid_synth_program_change`. No-op if the synth failed to
    /// initialise.
    ///
    /// - Parameters:
    ///   - channel: MIDI channel 0–15.
    ///   - program: GM program number 0–127.
    public func setProgram(channel: UInt8, program: UInt8) {
        guard let synth else { return }
        fluid_synth_program_change(synth, Int32(channel), Int32(program))
    }

    /// Builds an `AVAudioSourceNodeRenderBlock` to plug into an
    /// `AVAudioSourceNode`.
    ///
    /// The block is `@Sendable`; it captures the renderer (which is
    /// `@unchecked Sendable`) so the closure inherits no actor isolation.
    /// Each invocation drains all pending MIDI events from the ring,
    /// dispatches them to FluidSynth, then renders `frameCount` stereo
    /// frames into the supplied buffer list (non-interleaved Float32).
    ///
    /// - Parameter format: The downstream `AVAudioFormat`. Reserved for
    ///   future use; the current implementation assumes 2-channel
    ///   non-interleaved Float32 (the AVAudioEngine standard format).
    /// - Returns: A `@Sendable` render block suitable for
    ///   `AVAudioSourceNode(format:renderBlock:)`.
    public func makeRenderBlock(format: AVAudioFormat) -> AVAudioSourceNodeRenderBlock {
        _ = format  // format parameter reserved for future channel-count handling
        let renderer = self  // capture self by reference; @unchecked Sendable
        let block: AVAudioSourceNodeRenderBlock = { isSilence, _, frameCount, audioBufferList in
            renderer.drainPendingMIDI()
            guard let synth = renderer.synth else {
                isSilence.pointee = true
                return noErr
            }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Standard format → 2 buffers, non-interleaved Float32
            guard abl.count >= 2 else { return noErr }
            let leftPtr = abl[0].mData!.assumingMemoryBound(to: Float.self)
            let rightPtr = abl[1].mData!.assumingMemoryBound(to: Float.self)
            // fluid_synth_write_float: dest_l, off_l, incr_l, dest_r, off_r, incr_r
            _ = fluid_synth_write_float(
                synth, Int32(frameCount),
                UnsafeMutableRawPointer(leftPtr), 0, 1,
                UnsafeMutableRawPointer(rightPtr), 0, 1
            )
            return noErr
        }
        return block
    }

    // MARK: - Private Methods

    /// Drains all pending MIDI events from the ring, dispatching them to
    /// FluidSynth via direct C calls. Called from the render block on the
    /// CoreAudio realtime thread.
    private func drainPendingMIDI() {
        guard let synth else { return }
        while let event = ring.dequeue() {
            let high = event.status & 0xF0
            let ch = Int32(event.channel)
            switch high {
            case 0x90:
                // Note-on with vel 0 conventionally means note-off
                if event.data2 == 0 {
                    fluid_synth_noteoff(synth, ch, Int32(event.data1))
                } else {
                    fluid_synth_noteon(synth, ch, Int32(event.data1), Int32(event.data2))
                }
            case 0x80:
                fluid_synth_noteoff(synth, ch, Int32(event.data1))
            case 0xC0:
                fluid_synth_program_change(synth, ch, Int32(event.data1))
            case 0xB0:
                fluid_synth_cc(synth, ch, Int32(event.data1), Int32(event.data2))
            case 0xE0:
                let bend = (Int32(event.data2) << 7) | Int32(event.data1)
                fluid_synth_pitch_bend(synth, ch, bend)
            default:
                break  // poly pressure, channel pressure, etc.
            }
        }
    }
}
