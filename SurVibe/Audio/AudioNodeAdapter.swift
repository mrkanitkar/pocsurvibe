import AudioKit
import AVFoundation
import SVAudio
import SVCore
import os.log

/// Wraps the app's single AVAudioEngine's mainMixerNode as an AudioKit Node.
///
/// AudioKitUI visualization views (SpectrogramView, NodeOutputView, NodeFFTView)
/// require an AudioKit `Node` as input. This adapter bridges our AVFoundation-based
/// AudioEngineManager to AudioKit's visualization layer without creating a second
/// engine or modifying existing audio routing.
///
/// The adapter taps `mainMixerNode` (not `inputNode`), so it coexists with the
/// existing pitch detection mic tap on `inputNode` bus 0. One tap per bus per node
/// is the AVAudioEngine constraint — different nodes can have simultaneous taps.
///
/// ## Data Source
/// The mainMixerNode carries all mixed audio: microphone input, SoundFont sampler,
/// tanpura drone, and metronome clicks. Visualization shows the full mix.
///
/// ## Thread Safety
/// All access must be on MainActor. The underlying AVAudioNode is accessed
/// through AudioEngineManager.shared which is also @MainActor-isolated.
@MainActor
final class AudioNodeAdapter: Node {
    // MARK: - Node Protocol

    /// The AVAudioNode that AudioKitUI views will tap for visualization data.
    var avAudioNode: AVAudioNode {
        AudioEngineManager.shared.engine.mainMixerNode
    }

    /// Node has no upstream AudioKit connections (we use AVFoundation routing).
    var connections: [Node] { [] }

    // MARK: - Properties

    /// Shared instance. Created lazily on first access.
    static let shared = AudioNodeAdapter()

    /// Whether this adapter is currently connected and ready for visualization.
    private(set) var isConnected = false

    private static let logger = Logger.survibe(category: "AudioNodeAdapter")

    // MARK: - Initialization

    private init() {}

    // MARK: - Lifecycle

    /// Prepare the adapter for visualization use.
    ///
    /// Verifies the audio engine is running and the mainMixerNode has a valid
    /// format. AudioKitUI views will install their own taps on this node.
    ///
    /// - Throws: `AudioNodeAdapterError.engineNotRunning` if the engine is stopped.
    func connect() throws {
        guard AudioEngineManager.shared.isRunning else {
            throw AudioNodeAdapterError.engineNotRunning
        }
        isConnected = true
        Self.logger.info("AudioNodeAdapter connected to mainMixerNode")
    }

    /// Tear down the adapter. AudioKitUI views should be removed from the
    /// view hierarchy before calling this to avoid dangling taps.
    func disconnect() {
        isConnected = false
        Self.logger.info("AudioNodeAdapter disconnected")
    }
}

// MARK: - AudioNodeAdapterError

/// Errors specific to AudioNodeAdapter operations.
enum AudioNodeAdapterError: LocalizedError, Sendable {
    /// The audio engine must be running before connecting visualization.
    case engineNotRunning

    var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            "Audio engine must be running before connecting visualization"
        }
    }
}
