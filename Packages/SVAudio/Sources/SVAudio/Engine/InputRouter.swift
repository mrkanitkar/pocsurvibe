import Foundation
import SVCore
import os

private let routerLogger = Logger.survibe(category: "InputRouter")

/// Auto-routes input events from either MIDI (when a device is
/// connected) or the iPad microphone. Emits a single unified
/// `AsyncStream<InputEvent>` for `PlayAlongViewModel` to consume.
///
/// ## Behavior
///
/// - On `start()`: subscribes to `MIDIInputManager.connectionStateStream`
///   and `noteOnStream`. If a MIDI device is already connected, immediately
///   switches to `.midi`; otherwise starts the mic detector and switches
///   to `.mic`.
/// - On MIDI hot-plug: `connectionStateStream` yields true → `InputRouter`
///   stops the mic detector (saving battery and CPU) and switches to
///   `.midi(deviceName: ...)`.
/// - On MIDI disconnect: switches back to `.mic`, starts the detector.
///
/// ## MIDI/mic priority
///
/// MIDI wins over mic when both are available. This is the plan's spec
/// (option C: hybrid MIDI-first with mic fallback). The spec also calls
/// for a Settings toggle to override this, which is deferred to V2.
@MainActor
public final class InputRouter {
    /// The current active input source. Updated by `switchTo`.
    public private(set) var active: InputSource = .none

    /// Called on the main actor when `active` transitions.
    public var onSourceChange: ((InputSource) -> Void)?

    /// The unified event stream. Created lazily on first access.
    public var eventStream: AsyncStream<InputEvent> {
        if let existing = _eventStream { return existing }
        let (stream, cont) = AsyncStream<InputEvent>.makeStream()
        _eventStream = stream
        _eventContinuation = cont
        return stream
    }

    private var _eventStream: AsyncStream<InputEvent>?
    private var _eventContinuation: AsyncStream<InputEvent>.Continuation?

    private let micDetector: MicPitchDetector
    private var micTask: Task<Void, Never>?
    private var midiNoteTask: Task<Void, Never>?
    private var midiConnectTask: Task<Void, Never>?

    /// Robust mode flag — controls which gate the mic detector uses when
    /// switching to `.mic`. Updated externally (e.g. from Settings).
    public var robustModeEnabled: Bool = false

    /// When `true` (default), the router auto-switches between mic and MIDI
    /// based on device connection state. Set to `false` to lock the active
    /// source — used by screens that always want mic input (e.g. Learn-tab
    /// sing-along exercises) even when a MIDI device is plugged in.
    ///
    /// Must be set **before** `start()`. Changing it mid-session is a no-op
    /// until the next `stop()` / `start()` cycle.
    public var autoSwitchEnabled: Bool = true

    /// Reference pitch forwarded to the underlying `MicPitchDetector` on
    /// each mic activation. Defaults to A4 = 440 Hz.
    public var referencePitch: Double = 440.0 {
        didSet { micDetector.referencePitch = referencePitch }
    }

    /// Optional secondary ring buffer that receives a copy of every mic
    /// sample delivered to the tap.
    ///
    /// Set before `start()` when a caller needs a parallel pipeline (e.g.
    /// chord detection via `ChromagramDSP`) alongside the router's mono
    /// pitch stream. Forwards directly to the underlying
    /// `MicPitchDetector.secondaryRingBuffer`. Cleared on `stop()`.
    public var secondaryMicRingBuffer: SPSCRingBuffer? {
        get { micDetector.secondaryRingBuffer }
        set { micDetector.secondaryRingBuffer = newValue }
    }

    /// Live sample rate captured by the underlying mic tap.
    ///
    /// Exposed so callers of `secondaryMicRingBuffer` can run their own
    /// DSP at the same rate as the shared tap (avoids a hardcoded 44100
    /// assumption). Atomic, lock-free — readable from any context.
    public var liveSampleRate: AtomicDoubleBox { micDetector.liveSampleRate }

    public init(micDetector: MicPitchDetector = MicPitchDetector()) {
        self.micDetector = micDetector
    }

    /// Start the router: begin MIDI monitoring and pick an initial source.
    public func start() {
        // Prime the event stream so callers' `for await` begins correctly.
        _ = eventStream

        // Start the MIDI input manager if not already started.
        MIDIInputManager.shared.start()

        // Watch MIDI connection state — auto-switch only when enabled. Even
        // with auto-switch disabled, we still observe the stream so that
        // `onSourceChange` consumers can surface "MIDI device is connected"
        // metadata without hijacking the active audio path.
        let autoSwitch = autoSwitchEnabled
        midiConnectTask = Task { [weak self] in
            for await connected in MIDIInputManager.shared.connectionStateStream {
                guard let self else { break }
                if autoSwitch {
                    if connected {
                        let name = MIDIInputManager.shared.connectedDeviceName ?? "MIDI Device"
                        self.switchTo(.midi(deviceName: name))
                    } else {
                        self.switchTo(.mic)
                    }
                }
            }
        }

        // Forward MIDI note events to the unified stream.
        midiNoteTask = Task { [weak self] in
            for await event in MIDIInputManager.shared.noteOnStream {
                guard let self else { break }
                self.forwardMIDINote(event)
            }
        }

        // Initial state: when auto-switch is off, always start with mic.
        // Otherwise honor the current MIDI connection state.
        if autoSwitch, MIDIInputManager.shared.isConnected {
            let name = MIDIInputManager.shared.connectedDeviceName ?? "MIDI Device"
            switchTo(.midi(deviceName: name))
        } else {
            switchTo(.mic)
        }
    }

    /// Stop routing: cancel tasks, stop the mic detector, finish the stream.
    public func stop() {
        midiConnectTask?.cancel()
        midiConnectTask = nil
        midiNoteTask?.cancel()
        midiNoteTask = nil
        micTask?.cancel()
        micTask = nil
        micDetector.stop()
        _eventContinuation?.finish()
        _eventContinuation = nil
        _eventStream = nil
        active = .none
        routerLogger.info("InputRouter stopped")
    }

    /// Force a specific source, overriding auto-selection.
    ///
    /// Used by UI override sheets (e.g. "Force Microphone" when the user
    /// wants to sing over a MIDI backing). Stays in effect until the next
    /// `switchTo` call triggered by auto-selection.
    public func forceSource(_ source: InputSource) {
        switchTo(source)
    }

    // MARK: - Private

    /// Transition to a new active source. Stops the previous source's
    /// pipeline and starts the new one.
    private func switchTo(_ newSource: InputSource) {
        guard newSource != active else { return }
        routerLogger.info(
            "Source transition: \(String(describing: self.active)) -> \(String(describing: newSource))"
        )

        // Tear down the outgoing source.
        switch active {
        case .mic:
            micDetector.stop()
            micTask?.cancel()
            micTask = nil
        case .midi, .none:
            break
        }

        active = newSource
        onSourceChange?(newSource)

        // Bring up the incoming source.
        switch newSource {
        case .mic:
            // Apply current robust mode preference before starting.
            micDetector.robustGate = robustModeEnabled
                ? SoundAnalysisGate() as any RobustPitchGate
                : DefaultRobustPitchGate()
            let stream = micDetector.start()
            micTask = Task { [weak self] in
                for await result in stream {
                    self?._eventContinuation?.yield(.pitch(result: result, source: .mic))
                }
            }
        case .midi, .none:
            // MIDI note forwarding is always active via midiNoteTask;
            // nothing to start here. `.none` tears everything down.
            break
        }
    }

    /// Convert a `MIDIInputEvent` into an `InputEvent.noteOn/.noteOff`
    /// and forward to the unified stream. Only forwards when MIDI is
    /// the active source — otherwise the event is suppressed.
    private func forwardMIDINote(_ event: MIDIInputEvent) {
        guard case .midi = active else { return }
        let timestamp = UInt64(DispatchTime.now().uptimeNanoseconds)
        if event.velocity > 0 {
            _eventContinuation?.yield(
                .noteOn(
                    note: Int(event.noteNumber),
                    velocity: Int(event.velocity),
                    source: active,
                    timestampNs: timestamp
                )
            )
        } else {
            _eventContinuation?.yield(
                .noteOff(note: Int(event.noteNumber), source: active, timestampNs: timestamp)
            )
        }
    }
}
