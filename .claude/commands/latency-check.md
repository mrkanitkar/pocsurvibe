# /latency-check — Verify audio latency paths against SurVibe's 3-10ms target

Audit all audio latency paths and verify they meet SurVibe's performance budget.

## When to use

- Before any release or TestFlight build
- After changes to `AudioEngineManager`, `AudioSessionManager`, `SoundFontManager`, `MetronomePlayer`, `SongPlaybackEngine`, `MicPitchDetector`, or `MIDIInputManager`
- When users report audio lag or timing issues

## Latency Budget

| Path | Target | Components | How Measured |
|------|--------|-----------|-------------|
| MIDI key → sound | <10ms | Hardware I/O buffer + AVAudioUnitSampler render | `AudioSessionManager.ioBufferDuration` × sampleRate + sampler overhead |
| MIDI key → UI highlight | <10ms | MIDI callback → NSLock → @MainActor dispatch | Negligible (~1-3ms for main thread scheduling) |
| Mic → pitch result | <30ms | Mic tap buffer size + DSP processing time | `bufferSize / sampleRate` + autocorrelation time |
| Mic → note match | <50ms | Pitch result + SwarUtility + NoteScoreCalculator | Pitch latency + O(1) scoring |
| Note scheduling jitter | <1ms | AVAudioTime sample-accurate scheduling | No jitter if AVAudioTime used; ~10ms if Task.sleep |
| Metronome beat accuracy | <0.1ms | Pre-scheduled AVAudioTime on audio timeline | Look-ahead pattern eliminates wall-clock jitter |

## Steps

### 1. Verify Hardware I/O Buffer

Read `AudioSessionManager.swift` and check:
- [ ] `preferredIOBufferDuration` is set to `256.0 / 44100.0` (~5.8ms)
- [ ] Verify with: `let actualDuration = AVAudioSession.sharedInstance().ioBufferDuration`
- [ ] Calculate actual latency: `actualDuration × 1000` ms

**Expected:** ~5.8ms requested, system may grant 5.3-5.8ms.

### 2. Verify Pitch Detection Latency

Read `AudioEngineManager.swift` mic tap installation:
- [ ] Tap buffer size: should be 1024 samples for melody detection
- [ ] Calculate: `1024 / 44100 = 23.2ms` hardware capture latency
- [ ] DSP processing on `.userInteractive` queue: typically <5ms for autocorrelation
- [ ] **Total mic→pitch: ~28ms** (within 30ms target)

Read `MicPitchDetector.swift`:
- [ ] Uses `SPSCRingBuffer` (lock-free) for sample transfer from the mic tap to the DSP task
- [ ] DSP dispatch queue QoS is `.userInteractive`
- [ ] Continuation yield happens on processing queue, not render thread

### 3. Verify Note Scheduling

Read `MetronomePlayer.swift`:
- [ ] Uses `AVAudioTime(sampleTime:atRate:)` for scheduling
- [ ] Look-ahead pattern pre-schedules multiple beats
- [ ] **No `Task.sleep` or `DispatchQueue.asyncAfter`** for timing

Read `SongPlaybackEngine.swift`:
- [ ] Check if uses `AVAudioTime` or `Task.sleep`
- [ ] If `Task.sleep`: flag as P1 — ~10ms jitter from cooperative scheduling
- [ ] Compare to MetronomePlayer pattern (the correct reference)

### 4. Verify MIDI-to-Sound Path

Read `MIDIInputManager.swift` → `SoundFontManager.swift`:
- [ ] MIDI noteOn callback → direct `sampler.startNote()` call
- [ ] No async dispatch between MIDI callback and sampler
- [ ] SoundFont loaded and ready (not lazy-loaded on first note)
- [ ] **Total: hardware I/O (~5.8ms) + sampler render (<1ms) = ~6.8ms**

### 5. Check for OSSignposter Instrumentation

Search for `OSSignposter` usage:
```
grep -r "OSSignposter\|signposter\|beginInterval\|endInterval" Packages/SVAudio/ SurVibe/Playback/ SurVibe/Practice/
```

- [ ] Pitch detection loop has signpost interval
- [ ] FFT/chromagram computation has signpost interval
- [ ] SongPlaybackEngine note scheduling has signpost interval
- [ ] If missing: flag as P1 (can't measure actual latency without instrumentation)

### 6. Run Latency Smoke Test

If tests are available, run audio-related tests:
```
swift test --filter "Latency\|Buffer\|Timing\|Audio" --package-path Packages/SVAudio
```

Check for:
- Buffer size validation tests
- Timing accuracy tests (if any)
- Engine lifecycle tests

## Output format

```
## Latency Check Report

### Path Analysis

| Path | Target | Calculated | Status | Evidence |
|------|--------|-----------|--------|----------|
| MIDI → sound | <10ms | Xms | PASS/FAIL | file:line |
| MIDI → UI | <10ms | Xms | PASS/FAIL | file:line |
| Mic → pitch | <30ms | Xms | PASS/FAIL | file:line |
| Mic → match | <50ms | Xms | PASS/FAIL | file:line |
| Note jitter | <1ms | Xms | PASS/FAIL | file:line |
| Metronome | <0.1ms | Xms | PASS/FAIL | file:line |

### Configuration Verified
- I/O Buffer: X frames (Yms)
- Pitch Buffer: X samples (Yms)
- DSP Queue QoS: .userInteractive
- Ring Buffer Type: SPSCRingBuffer

### Instrumentation Status
- [ ] OSSignposter present for pitch detection
- [ ] OSSignposter present for FFT
- [ ] OSSignposter present for note scheduling

### Issues Found
- [file:line] Issue → Impact on latency → Fix

### Summary
X paths checked, Y within budget, Z over budget
```
