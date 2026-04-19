# Foundation Primitives — SurVibe

Reuse these; do not reinvent.

## HapticEngine

- **Location:** `Packages/SVCore/Sources/SVCore/Accessibility/HapticEngine.swift:9`
- **Shape:** `public final class HapticEngine` with `public static let shared`. Wraps three `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` instances.
- **Usage (MainActor):** `HapticEngine.shared.impact(.light)` at user-visible state transitions.
- **Don't:** call from an audio tap, MIDI callback, or any non-main actor. Always hop to MainActor first.

## SPSCRingBuffer

- **Location:** `Packages/SVAudio/Sources/SVAudio/Pitch/SPSCRingBuffer.swift:7`
- **Shape:** lock-free single-producer, single-consumer ring buffer.
- **Usage:** cross-actor handoff of audio frames, note events, or any high-frequency producer/consumer pair where lock contention is unacceptable.
- **Don't:** use with multiple producers or multiple consumers. Don't hold references across struct copies.

## LatencyProbe & LatencyHistogram

- **Location:** `Packages/SVAudio/Sources/SVAudio/Diagnostics/LatencyProbe.swift:19`
- **Shape:** pipeline-wide latency collection via `ProbeToken` stages (input → DSP → match → frame). `LatencyProbe.shared.record(_:)`. `stageSummary(from:)` for per-stage breakdown.
- **Usage:** stamp a `ProbeToken` at each pipeline stage in order; record it when complete. `OSSignposter` output in Instruments for profiling runs.
- **Don't:** use for synchronous measurement in unit tests — there is no `measure(iterations:)` helper. For regression tests, use `MockAudioEngineProvider.startCallCount` style spies.

## MagnificationGesture (pinch-to-zoom notation)

- **Location:** `SurVibe/Notation/NotationContainerView.swift:171`
- **Shape:** `MagnificationGesture()` composed with `@GestureState`, clamped 0.5x–3.0x.
- **Usage:** reuse this pattern in any notation-surface view. `ScrollingSheetView` should inherit the gesture (SP-4 item).
- **Don't:** reimplement; wrap the container or lift the modifier.

---

_Last updated: 2026-04-19. Landed as part of SP-0 Foundation._
