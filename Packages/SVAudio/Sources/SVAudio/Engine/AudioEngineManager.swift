import AVFoundation
import AudioToolbox
import SVCore
import os.log

/// Nonisolated global holding the sampler's MIDI schedule block.
///
/// Written only on the main actor during `AudioEngineManager`'s engine
/// lifecycle (start / stop / route change). Read from the CoreMIDI
/// high-priority thread in the MIDI parse callback to inject events
/// directly into the sampler's render cycle.
///
/// `nonisolated(unsafe)` is justified because:
/// 1. Writes are serialized by @MainActor isolation.
/// 2. Reads see a single pointer-sized value — no tearing possible.
/// 3. The block itself is thread-safe per Apple's AUAudioUnit contract.
nonisolated(unsafe) var samplerMIDIScheduleBlock: AUScheduleMIDIEventBlock?

/// Central audio engine manager using a single AVAudioEngine instance.
/// Uses @MainActor isolation for thread-safe state access.
///
/// Node graph (per WWDC 2014/2019 best practice — single engine):
/// - AVAudioInputNode (mic, tap at 44100 Hz)
/// - ProductionMultiChannelEngine subgraph (up to 16 AVAudioUnitSamplers via MuseScore_General)
/// - AVAudioPlayerNode x2 (tanpura, metronome)
/// - Main mixer with per-node volume
///
/// ## AUD-005: Buffer Size Architecture
///
/// Two different buffer sizes coexist in the audio pipeline:
///
/// **Hardware I/O buffer (AudioSession):** Configured to 256 frames (~5.8ms at 44100 Hz)
/// via `AVAudioSession.setPreferredIOBufferDuration(256 / 44100)`. This is the latency
/// between hardware sample capture and the first available frame — low latency is critical
/// for responsive SoundFont MIDI playback.
///
/// **Mic tap buffer (`bufferSize = 1024`):** The `installMicTap(bufferSize:)` parameter
/// requests 1024 frames (~23ms) per audio tap callback. This is the DSP analysis window.
/// At 44100 Hz the lowest musically useful pitch within `PracticeConstants.minimumFrequency`
/// (50 Hz) has a period of ~882 samples; the autocorrelation half-window of 512 lag
/// samples covers pitches down to ~86 Hz. Notes below 86 Hz (roughly F2) are not in the
/// singing/playing range targeted by SurVibe's piano tutor, so detection accuracy is
/// preserved for the practical range (C3–C8). Halving the buffer from 2048→1024 cuts
/// the minimum end-to-end detection latency from ~46 ms to ~23 ms, which is the single
/// largest factor in the perceived "lag" reported by users playing at normal BPM.
///
/// These two values are **independent**: the hardware I/O buffer controls playback
/// latency; the tap buffer controls pitch detection accuracy. They do not need to match.
@MainActor
public final class AudioEngineManager: AudioEngineProviding {

    // MARK: - Engine Mode

    /// Tracks the audio session category the engine was started with.
    ///
    /// When the engine is running in `.playbackOnly` mode and a caller
    /// requests `.playAndRecord` (via `start()`), the engine must be
    /// stopped and restarted so iOS configures the audio route for
    /// microphone input.
    private enum EngineMode {
        /// Engine is not running.
        case stopped
        /// Engine running with `.playback` session — no mic input available.
        case playbackOnly
        /// Engine running with `.playAndRecord` session — mic input available.
        case playAndRecord
    }

    // MARK: - Properties

    public static let shared = AudioEngineManager()

    /// The single AVAudioEngine instance.
    public let engine = AVAudioEngine()

    /// Production multi-channel audio engine. Lazily constructed on the first
    /// `startForPlayback()` call after `engine.start()` succeeds.
    ///
    /// Lives for the app process lifetime — there is no teardown path. The
    /// only audio destination for SF2 playback in this codebase. All five
    /// production audio surfaces (Play-Along, Song Playback, Practice
    /// listen-first, Interactive Piano, Isomorphic Sargam) plus USB MIDI
    /// keyboard input route through here.
    public private(set) var multiChannel: ProductionMultiChannelEngine?

    /// Player node for tanpura drone.
    public let tanpuraNode = AVAudioPlayerNode()

    /// Player node for metronome clicks.
    public let metronomeNode = AVAudioPlayerNode()

    /// Default buffer size for mic tap: 1024 frames (~23ms at 44100 Hz).
    ///
    /// Reduced from 2048 to halve end-to-end detection latency. Covers pitches
    /// down to ~86 Hz, which includes the full practical piano range (C3–C8).
    public let bufferSize: AVAudioFrameCount = 1024

    /// RT-safe MIDI schedule block for the sampler, exposed via the
    /// nonisolated global `samplerMIDIScheduleBlock` so CoreMIDI callbacks
    /// (running on their own high-priority thread) can invoke it without
    /// crossing MainActor isolation.
    ///
    /// Captured after `engine.prepare()`; cleared on `stop()`.
    public var samplerMIDIBlock: AUScheduleMIDIEventBlock? {
        get { samplerMIDIScheduleBlock }
        set { samplerMIDIScheduleBlock = newValue }
    }

    private var isConfigured = false

    /// Whether a microphone tap is currently installed on the input node.
    ///
    /// Exposed as public read-only so other components can guard against
    /// attempting to install a second tap while one is already active.
    public private(set) var hasMicTap = false

    /// Current engine mode — tracks which audio session category is active.
    private var currentMode: EngineMode = .stopped

    /// Stored mic tap handler for reinstallation after route changes.
    private var micTapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    /// Stored mic tap buffer size for reinstallation after route changes.
    private var micTapBufferSize: AVAudioFrameCount?

    private static let logger = Logger.survibe(category: "AudioEngine")

    // MARK: - Initialization

    private init() {
        // Attach nodes only — defer connections to start() after session is configured
        engine.attach(tanpuraNode)
        engine.attach(metronomeNode)
    }

    // MARK: - Private Methods

    /// Connect all nodes to main mixer using the current audio session format.
    /// Must be called after audio session is configured.
    private func connectNodes() {
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)

        engine.connect(tanpuraNode, to: mainMixer, format: format)
        engine.connect(metronomeNode, to: mainMixer, format: format)
        isConfigured = true
    }

    /// Disconnect and reconnect all nodes with the current session format.
    ///
    /// Called when the audio route changes (Bluetooth connect/disconnect,
    /// headphones plugged in) so nodes use the newly negotiated format.
    private func reconnectNodes() {
        let mainMixer = engine.mainMixerNode
        engine.disconnectNodeOutput(tanpuraNode)
        engine.disconnectNodeOutput(metronomeNode)

        let format = mainMixer.outputFormat(forBus: 0)
        engine.connect(tanpuraNode, to: mainMixer, format: format)
        engine.connect(metronomeNode, to: mainMixer, format: format)

        Self.logger.info(
            "Nodes reconnected with format: rate=\(format.sampleRate) ch=\(format.channelCount)"
        )
    }

    /// Wire up audio session interruption and route-change handlers.
    ///
    /// Extracted from `start()` and `startForPlayback()` to avoid duplication.
    private func setupInterruptionAndRouteHandlers() {
        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in
            Task { @MainActor in
                self?.engine.pause()
            }
        }
        AudioSessionManager.shared.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor in
                if shouldResume {
                    do {
                        try self?.engine.start()
                        Self.logger.info("Engine restarted after interruption")
                    } catch {
                        Self.logger.error(
                            "Engine restart after interruption failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        }
        AudioSessionManager.shared.onRouteChange = { [weak self] in
            Task { @MainActor in
                self?.handleRouteChange()
            }
        }
    }

    /// Handle an audio route change by reconnecting nodes with the new format.
    ///
    /// AUD-015: Compares the mixer's output format before and after the route
    /// change. If the format (sample rate + channel count) is unchanged, node
    /// reconnection is skipped entirely — no engine pause, no tap reinstall.
    /// This avoids unnecessary audio glitches on headphone insertions that do
    /// not change the stream format (e.g., wired headphones at the same rate).
    ///
    /// Pauses the engine, reconnects nodes, restarts the engine, and
    /// reinstalls the mic tap if one was active before the route change.
    private func handleRouteChange() {
        guard engine.isRunning else {
            Self.logger.info("Route changed but engine not running — skipping")
            return
        }

        // AUD-015: Skip reconnection if the format hasn't changed.
        let currentFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let previousRate = currentFormat.sampleRate
        let previousChannels = currentFormat.channelCount

        // Force the mixer to reflect the new hardware route by accessing inputNode,
        // which triggers iOS to reconfigure the format negotiation.
        let newFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        if newFormat.sampleRate == previousRate, newFormat.channelCount == previousChannels {
            let rate = newFormat.sampleRate
            let ch = newFormat.channelCount
            Self.logger.info(
                "Route changed, format unchanged (rate=\(rate) ch=\(ch)) — skip reconnect"
            )
            return
        }

        Self.logger.info(
            "Audio route changed — format changed (\(previousRate)->\(newFormat.sampleRate) Hz) — reconnecting nodes"
        )

        // Remember mic tap state before pausing
        let hadMicTap = hasMicTap
        let savedHandler = micTapHandler
        let savedBufferSize = micTapBufferSize

        // Remove existing mic tap before reconnecting
        if hasMicTap {
            engine.inputNode.removeTap(onBus: 0)
            hasMicTap = false
        }

        engine.pause()
        reconnectNodes()

        do {
            engine.prepare()
            try engine.start()
            Self.logger.info("Engine restarted after route change")
        } catch {
            Self.logger.error(
                "Engine restart after route change failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        // Reinstall mic tap if one was active
        if hadMicTap, let handler = savedHandler {
            let reinstalled = installMicTap(bufferSize: savedBufferSize, handler: handler)
            if reinstalled {
                Self.logger.info("Mic tap reinstalled after route change")
            } else {
                Self.logger.error("Failed to reinstall mic tap after route change")
            }
        }
    }

    // MARK: - Public Methods

    /// Start the audio engine with microphone input. Configures audio session
    /// with `.playAndRecord` category, then connects nodes and starts.
    ///
    /// If the engine is already running in playback-only mode (started via
    /// `startForPlayback()`), it is stopped and restarted with the correct
    /// audio session category so iOS configures the route for mic input.
    ///
    /// Important: Accesses `engine.inputNode` before `engine.start()` to ensure
    /// iOS configures the audio route for microphone input. Without this, the
    /// input node may report 0 channels when `installMicTap` is called later.
    public func start() throws {
        MultiChannelLog.shared.log(.info, ">>> AudioEngineManager.start() currentMode=\(currentMode)")
        defer {
            MultiChannelLog.shared.log(
                .info,
                "<<< AudioEngineManager.start() exit currentMode=\(currentMode) isRunning=\(engine.isRunning)"
            )
        }
        // If already running in playAndRecord mode, nothing to do.
        if currentMode == .playAndRecord {
            Self.logger.info("start() called — already in playAndRecord mode, skipping")
            return
        }

        // If running in playbackOnly mode, must stop engine first so iOS
        // can reconfigure the audio route for microphone input.
        if currentMode == .playbackOnly {
            Self.logger.info("start() called — upgrading from playbackOnly to playAndRecord")
            engine.pause()
            engine.stop()
            // Disconnect nodes so they can be reconnected with new format
            isConfigured = false
        } else {
            Self.logger.info("start() called — engine was stopped")
        }

        try AudioSessionManager.shared.configure()
        MultiChannelLog.shared.log(.info, "... start: session configured for recording")
        Self.logger.info("Audio session configured for playAndRecord")

        // Reconnect nodes after session reconfiguration so format is valid
        if !isConfigured {
            connectNodes()
            MultiChannelLog.shared.log(.info, "... start: nodes connected")
            Self.logger.info("Nodes connected")
        }

        // CRITICAL: Access inputNode BEFORE engine.start() so iOS knows
        // we need mic input and configures the audio route accordingly.
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Self.logger.info(
            "Input node format: rate=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)"
        )

        setupInterruptionAndRouteHandlers()

        engine.prepare()
        MultiChannelLog.shared.log(.info, "... start: engine prepared")
        MultiChannelLog.shared.log(.info, "... start: calling engine.start()")
        try engine.start()
        MultiChannelLog.shared.log(.info, "... start: engine.start() returned")
        currentMode = .playAndRecord

        // USB MIDI input direct-wires through the touch sampler (samplers[0])
        // for sub-6 ms audible echo. Phase 3 retired the legacy .sampler.
        MultiChannelLog.shared.log(.info, "... start: capturing samplerMIDIBlock")
        samplerMIDIBlock = multiChannel?.samplers[0].auAudioUnit.scheduleMIDIEventBlock
        let blockNonNil = samplerMIDIBlock != nil
        let mcNil = multiChannel == nil
        MultiChannelLog.shared.log(
            .info,
            "... start: samplerMIDIBlock captured non-nil=\(blockNonNil) multiChannelNil=\(mcNil)"
        )

        #if canImport(AVFAudio)
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let outputs = route.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
        let outVolStr = String(format: "%.2f", session.outputVolume)
        MultiChannelLog.shared.log(
            .info,
            "... start: AUDIO-ROUTE cat=\(session.category.rawValue) "
                + "mode=\(session.mode.rawValue) outVol=\(outVolStr) outs=[\(outputs)]"
        )
        #endif

        Self.logger.info("Engine started in playAndRecord mode, isRunning=\(self.engine.isRunning)")
    }

    /// Start the audio engine for playback only (no microphone input).
    ///
    /// Configures the audio session with `.playback` category and starts the
    /// engine without accessing `inputNode`. This avoids triggering a microphone
    /// permission prompt and is suitable for SoundFont-based MIDI playback.
    ///
    /// Safe to call multiple times — returns immediately if already running.
    /// If the engine is already running in `.playAndRecord` mode, returns
    /// immediately because that mode is a superset of playback.
    public func startForPlayback() throws {
        MultiChannelLog.shared.log(.info, ">>> AudioEngineManager.startForPlayback() currentMode=\(currentMode)")
        defer {
            MultiChannelLog.shared.log(
                .info,
                "<<< AudioEngineManager.startForPlayback() exit currentMode=\(currentMode) isRunning=\(engine.isRunning)"
            )
        }
        // playAndRecord is a superset — no downgrade needed.
        if currentMode == .playAndRecord {
            Self.logger.info("startForPlayback() — already in playAndRecord mode, skipping")
            return
        }

        // Already running in playback mode — nothing to do.
        if currentMode == .playbackOnly {
            Self.logger.info("startForPlayback() — already in playbackOnly mode, skipping")
            return
        }

        Self.logger.info("startForPlayback() called — engine was stopped")
        try AudioSessionManager.shared.configureForPlayback()
        MultiChannelLog.shared.log(.info, "... startForPlayback: session configured for recording")
        Self.logger.info("Audio session configured for playback")

        if !isConfigured {
            connectNodes()
            MultiChannelLog.shared.log(.info, "... startForPlayback: nodes connected")
            Self.logger.info("Nodes connected")
        }

        setupInterruptionAndRouteHandlers()

        engine.prepare()
        MultiChannelLog.shared.log(.info, "... startForPlayback: engine prepared")
        MultiChannelLog.shared.log(.info, "... startForPlayback: calling engine.start()")
        try engine.start()
        MultiChannelLog.shared.log(.info, "... startForPlayback: engine.start() returned")
        currentMode = .playbackOnly

        // Lazily construct the production multi-channel engine on first start.
        // Runs after engine.start() and currentMode set so the engine is fully
        // configured before attaching the multiChannel graph. Failure here is
        // non-fatal — samplerMIDIBlock is set to nil via optional-chaining so
        // USB MIDI is silenced rather than crashing when construction fails.
        MultiChannelLog.shared.log(.info, "... startForPlayback: checking multiChannel")
        if multiChannel == nil {
            do {
                self.multiChannel = try ProductionMultiChannelEngine(engine: engine)
                MultiChannelLog.shared.log(
                    .info, "... startForPlayback: multiChannel constructed=\(multiChannel != nil)"
                )
                Self.logger.info("multiChannel engine constructed")
            } catch {
                MultiChannelLog.shared.log(
                    .info,
                    "... startForPlayback: multiChannel CONSTRUCTION FAILED: \(error.localizedDescription)"
                )
                Self.logger.error(
                    "multiChannel construction failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        } else {
            MultiChannelLog.shared.log(.info, "... startForPlayback: multiChannel ALREADY exists")
        }

        // USB MIDI input direct-wires through the touch sampler (samplers[0])
        // for sub-6 ms audible echo. Phase 3 retired the legacy .sampler.
        MultiChannelLog.shared.log(.info, "... startForPlayback: capturing samplerMIDIBlock")
        samplerMIDIBlock = multiChannel?.samplers[0].auAudioUnit.scheduleMIDIEventBlock
        MultiChannelLog.shared.log(
            .info, "... startForPlayback: samplerMIDIBlock captured non-nil=\(samplerMIDIBlock != nil)"
        )

        Self.logger.info("Engine started in playbackOnly mode, isRunning=\(self.engine.isRunning)")
    }

    /// Stop the audio engine and remove any installed taps.
    public func stop() {
        if hasMicTap {
            engine.inputNode.removeTap(onBus: 0)
            hasMicTap = false
            micTapHandler = nil
            micTapBufferSize = nil
        }
        if engine.isRunning {
            tanpuraNode.stop()
            metronomeNode.stop()
            engine.stop()
        }
        // Clear the MIDI schedule block — the AU is no longer initialized
        // in a valid render state until start()/startForPlayback() is
        // called again.
        samplerMIDIBlock = nil
        isConfigured = false
        currentMode = .stopped
        AudioSessionManager.shared.deactivate()
    }

    /// Whether the audio engine is currently running.
    public var isRunning: Bool {
        engine.isRunning
    }

    /// Install a tap on the mic input node for pitch detection.
    /// - Parameters:
    ///   - bufferSize: Number of frames per buffer (default: 2048)
    ///   - handler: Callback with audio buffer and time. Executes on real-time audio thread.
    /// - Returns: `true` if the tap was installed successfully, `false` otherwise.
    @discardableResult
    public func installMicTap(
        bufferSize: AVAudioFrameCount? = nil,
        handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) -> Bool {
        guard engine.isRunning else {
            Self.logger.error("installMicTap: engine not running")
            return false
        }

        let inputNode = engine.inputNode
        let tapBufferSize = bufferSize ?? self.bufferSize
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Guard against 0-channel format (mic not available or session misconfigured)
        guard inputFormat.channelCount > 0 else {
            Self.logger.error(
                "installMicTap: 0 channels — mic not available. sampleRate=\(inputFormat.sampleRate)"
            )
            return false
        }

        guard inputFormat.sampleRate > 0 else {
            Self.logger.error("installMicTap: sampleRate is 0")
            return false
        }

        Self.logger.info(
            "installMicTap: format=\(inputFormat.sampleRate)Hz ch=\(inputFormat.channelCount) buf=\(tapBufferSize)"
        )
        MIDIDiagBridge.recordLine(
            "[AUDIO] installMicTap format=\(inputFormat.sampleRate)Hz ch=\(inputFormat.channelCount) buf=\(tapBufferSize)"
        )
        #if canImport(AVFAudio)
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        MIDIDiagBridge.recordLine(
            """
            [AUDIO] session category=\(session.category.rawValue) mode=\(session.mode.rawValue) \
            inputGain=\(String(format: "%.2f", session.inputGain)) \
            isInputAvailable=\(session.isInputAvailable) \
            inputs=[\(inputs)] outputs=[\(outputs)]
            """
        )
        #endif

        // Remove existing tap if any — warn about replacement
        if hasMicTap {
            Self.logger.warning(
                "installMicTap: replacing existing mic tap — only one detector should be active at a time"
            )
            inputNode.removeTap(onBus: 0)
            hasMicTap = false
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: tapBufferSize,
            format: inputFormat,
            block: handler
        )
        hasMicTap = true

        // Store for reinstallation after route changes
        micTapHandler = handler
        micTapBufferSize = tapBufferSize

        Self.logger.info("Mic tap installed successfully")
        return true
    }

    /// Remove the mic input tap and clear stored handler.
    public func removeMicTap() {
        guard hasMicTap else { return }
        engine.inputNode.removeTap(onBus: 0)
        hasMicTap = false
        micTapHandler = nil
        micTapBufferSize = nil
    }

    /// Set volume for the touch sampler (samplers[0]) node (0.0 to 1.0).
    public func setSamplerVolume(_ volume: Float) {
        multiChannel?.samplers[0].volume = volume
    }

    /// Set volume for the tanpura node (0.0 to 1.0).
    public func setTanpuraVolume(_ volume: Float) {
        tanpuraNode.volume = volume
    }

    /// Set volume for the metronome node (0.0 to 1.0).
    public func setMetronomeVolume(_ volume: Float) {
        metronomeNode.volume = volume
    }
}
