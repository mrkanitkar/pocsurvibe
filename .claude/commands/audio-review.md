# /audio-review — Audio thread safety and latency review for SurVibe

Review audio-related code against Apple AVAudioEngine best practices, AudioKit v5 patterns, and SurVibe's latency budget.

## When to use

Run this after ANY change to files in:
- `Packages/SVAudio/`
- `SurVibe/Playback/`
- `SurVibe/Practice/`
- Any file importing `AVFoundation`, `AudioKit`, or `CoreMIDI`

## Steps

1. Identify audio-related changed files:
   ```
   git diff --name-only HEAD | grep -E '(SVAudio|Playback|Practice|Audio|MIDI|Pitch|Sound|Metronome|Tanpura)'
   ```

2. For each file, check against these rules:

### Audio Thread Safety (CRITICAL — P0)

These violations can cause audio glitches, deadlocks, or crashes on the real-time render thread.

- [ ] **No allocation on audio render thread** — tap callbacks and render callbacks must NOT:
  - Create Array, String, Dictionary, or any reference-counted object
  - Call `replaceSubrange()` (triggers COW allocation)
  - Use `append()` on Array (may reallocate)
  - Box closures or create Tasks
- [ ] **No locks on render thread** — tap callbacks must NOT:
  - Acquire `Mutex`, `NSLock`, `os_unfair_lock`, or `DispatchSemaphore`
  - Call `@MainActor`-isolated methods
  - Use `DispatchQueue.sync`
- [ ] **SPSCRingBuffer for audio data transfer** — data from tap callback to processing queue must use `SPSCRingBuffer` (lock-free, pre-allocated). Never use Mutex- or Array-backed buffers in the tap closure.
- [ ] **Tap callback is `@Sendable`** — mic tap handler must be annotated `@Sendable`
- [ ] **No `try?` on engine.start()** — must use `do/catch` with `logger.error`. Silent failure = user hears nothing

### Single Engine Rule

- [ ] **One AVAudioEngine** — all audio goes through `AudioEngineManager.shared.engine`
- [ ] **No second engine creation** — grep for `AVAudioEngine()` must return only `AudioEngineManager`
- [ ] **Attach before connect** — nodes attached in init, connected after session config
- [ ] **Input node accessed before start** — `engine.inputNode` triggers route config on iOS

### Buffer and Latency

- [ ] **Hardware I/O buffer** — `AudioSessionManager` uses 256 frames (~5.8ms at 44.1kHz)
- [ ] **Pitch detection buffer** — 1024 samples for melody, configurable for chords (1024/2048/4096/8192)
- [ ] **AVAudioTime scheduling** — note playback uses `AVAudioPlayerNode.scheduleBuffer(at: AVAudioTime)`, NOT `Task.sleep` or `DispatchQueue.asyncAfter`
- [ ] **Metronome uses look-ahead** — pre-schedules 4 beats on audio timeline for sample-accurate timing

### Route Change & Interruption

- [ ] **Route change handler** pauses, reconnects nodes, restarts engine, reinstalls mic tap
- [ ] **Interruption handler** pauses on `.began`, restarts on `.ended` with `shouldResume` check
- [ ] **Audio session fallback** — if `.playAndRecord` fails, try `.playback` with mic-unavailable flag

### Audio Session

- [ ] **Category:** `.playAndRecord` with options `[.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]`
- [ ] **Mode:** `.measurement` for pitch detection accuracy
- [ ] **Activation:** `setActive(true)` before engine start

### CoreMIDI Thread Safety

- [ ] **MIDIInputManager is NOT @MainActor** — CoreMIDI callbacks arrive on arbitrary threads
- [ ] **NSLock or Mutex** for mutable state in MIDI callbacks
- [ ] **`nonisolated(unsafe)` with documented safety** for any MIDI-related stored properties

### Logging

- [ ] **Logger present** in all audio files (subsystem: "com.survibe", category: component name)
- [ ] **No silent `try?`** — every `try?` in audio code must have a `logger.error` alternative
- [ ] **OSSignposter intervals** for performance-critical paths (pitch detection, FFT, note scheduling)

3. Check latency budget:

| Path | Target | How to Verify |
|------|--------|--------------|
| MIDI key → SoundFont sound | <10ms | 256-frame I/O buffer + AVAudioUnitSampler = ~6.8ms |
| MIDI key → visual highlight | <10ms | MIDIInputManager callback → @MainActor UI update |
| Mic → pitch detection result | <30ms | 1024-frame tap (~23ms) + DSP queue time |
| Mic → note match (practice) | <50ms | Pitch result → SwarUtility → NoteScoreCalculator |
| Song note → playback | <5ms jitter | Must use AVAudioTime, NOT Task.sleep |

4. Report findings:

## Output format
```
## Audio Review: <file list>

### CRITICAL (Audio Thread Safety)
- [file:line] Issue → Fix

### HIGH (Latency / Correctness)
- [file:line] Issue → Fix

### MEDIUM (Logging / Best Practice)
- [file:line] Issue → Fix

### Latency Budget
| Path | Target | Actual | Status |
|------|--------|--------|--------|

### Summary
X audio files reviewed, Y issues (Z critical thread-safety violations)
```
