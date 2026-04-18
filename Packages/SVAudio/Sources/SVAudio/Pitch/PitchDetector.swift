import Foundation

/// Protocol for pitch detection implementations.
///
/// Conforming types use `AsyncStream<PitchResult>` to deliver real-time
/// pitch detection results from the microphone. The stream yields results
/// at the audio buffer rate (~44 per second at 44100 Hz / 1024 samples).
///
/// **Lifecycle:**
/// 1. Call `start()` to begin detection. The returned stream emits `PitchResult` values.
/// 2. Consume the stream using `for await` or `.first(where:)`.
/// 3. Call `stop()` when detection is no longer needed. This also finishes the stream.
///
/// **Error behavior:** Implementations do not throw. If the audio engine is not
/// running or the mic tap cannot be installed, the stream may yield no results.
/// Check `PitchResult.amplitude` and `PitchResult.confidence` to distinguish
/// silence from detection failure.
///
/// **Implementations:**
/// - `MicPitchDetector`: Autocorrelation via `vDSP_dotpr` (primary, lower latency)
/// - `YINPitchDetector`: YIN algorithm via `Accelerate/vDSP` (fallback, better accuracy)
public protocol PitchDetectorProtocol: AnyObject {
    /// Start pitch detection and return a stream of results.
    ///
    /// Installs a mic tap on the shared `AudioEngineManager` and begins
    /// processing audio buffers. The stream uses `.bufferingNewest(1)` to
    /// ensure the consumer always sees the most recent detection.
    ///
    /// - Returns: An `AsyncStream` that yields `PitchResult` values until `stop()` is called.
    @MainActor func start() -> AsyncStream<PitchResult>

    /// Stop pitch detection and clean up resources.
    ///
    /// Removes the mic tap, finishes the `AsyncStream`, and resets internal state.
    /// Safe to call multiple times. After calling `stop()`, `start()` may be called again.
    @MainActor func stop()
}
