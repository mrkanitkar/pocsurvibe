# /audio-test — Audio-specific test suite for SurVibe

Run and validate audio-specific tests covering engine lifecycle, buffer safety, route change recovery, and timing accuracy.

## When to use

- After any changes to `Packages/SVAudio/`
- After changes to `SurVibe/Playback/` or `SurVibe/Practice/`
- Before any release or TestFlight build
- When audio tests are failing or flaky

## Steps

### 1. Run SVAudio Package Tests

```bash
cd /Users/maheshwar/Documents/Documentsmk/projects/SurVibe
swift test --package-path Packages/SVAudio 2>&1
```

Check that all tests pass. If failures, read the test file and diagnose.

### 2. Run Audio-Related App Tests

```bash
xcodebuild test \
  -project SurVibe.xcodeproj \
  -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SurVibeTests/AudioPipelineMemoryTests \
  -only-testing:SurVibeTests/StructuredLoggingTests \
  2>&1 | tail -30
```

### 3. Verify Test Coverage Categories

Check that tests exist for each audio subsystem:

#### Engine Lifecycle
- [ ] Engine start succeeds
- [ ] Engine stop cleans up nodes
- [ ] Engine restart after stop works
- [ ] Engine start with denied mic permission → graceful degradation
- [ ] Engine mode transitions: stopped → playbackOnly → playAndRecord

Search: `grep -r "engine.*start\|engine.*stop\|EngineMode\|engineManager" Packages/SVAudio/Tests/ SurVibeTests/`

#### Buffer Safety
- [ ] SPSCRingBuffer write/read cycle
- [ ] SPSCRingBuffer overflow handling (does not crash)
- [ ] SPSCRingBuffer concurrent producer/consumer
- [ ] Buffer power-of-two capacity enforcement
- [ ] AudioRingBuffer (if still used) — verify no allocation under lock

Search: `grep -r "RingBuffer\|SPSCRing\|AudioRingBuffer" Packages/SVAudio/Tests/`

#### Route Change Recovery
- [ ] Simulate route change notification → engine reconnects
- [ ] Headphone disconnect → switches to speaker
- [ ] Bluetooth connect/disconnect handling
- [ ] Audio session interruption → pause → resume

Search: `grep -r "routeChange\|interruption\|AVAudioSession.Notification" Packages/SVAudio/Tests/ SurVibeTests/`

#### Pitch Detection
- [ ] Known frequency → correct note name
- [ ] Below confidence threshold → nil result
- [ ] Buffer size affects frequency resolution
- [ ] Concurrent start/stop safety
- [ ] Memory: no growth over sustained detection

Search: `grep -r "PitchDetect\|pitchDetect\|frequency\|confidence" Packages/SVAudio/Tests/ SurVibeTests/`

#### Metronome Timing
- [ ] Beat scheduling uses AVAudioTime
- [ ] Tempo change updates scheduling interval
- [ ] Start/stop lifecycle clean

Search: `grep -r "Metronome\|metronome\|bpm\|tempo" Packages/SVAudio/Tests/ SurVibeTests/`

#### SoundFont Playback
- [ ] SoundFont loads successfully
- [ ] Note playback produces audio (non-nil buffer)
- [ ] MIDI program/bank selection

Search: `grep -r "SoundFont\|soundFont\|sampler\|AVAudioUnitSampler" Packages/SVAudio/Tests/ SurVibeTests/`

#### MIDI Input
- [ ] MIDI noteOn callback fires
- [ ] MIDI noteOff callback fires
- [ ] Thread safety: concurrent noteOn from multiple sources
- [ ] Connection/disconnection handling

Search: `grep -r "MIDI\|midi\|noteOn\|noteOff" Packages/SVAudio/Tests/ SurVibeTests/`

### 4. Check for Missing Test Categories

For each category above, if no tests found:
- Flag as **TEST GAP** with severity
- Suggest test structure using Swift Testing (`@Test`, `#expect`)

### 5. Check for Flaky Audio Tests

Audio tests are inherently timing-sensitive. Check for:
- [ ] No `Task.sleep` in test assertions (use `XCTestExpectation` or `#expect` with timeout)
- [ ] No hardcoded timing values that depend on CI speed
- [ ] Audio session mocking (tests shouldn't require real mic/speaker)
- [ ] Tests clean up audio resources in teardown

### 6. Memory Leak Check

If `AudioPipelineMemoryTests` exists, verify it:
- [ ] Creates and tears down audio pipeline
- [ ] Checks for deallocation (weak reference pattern)
- [ ] No growth over multiple cycles

## Output format

```
## Audio Test Report

### Test Results
| Suite | Tests | Pass | Fail | Skip |
|-------|------:|-----:|-----:|-----:|

### Coverage by Category
| Category | Tests Found | Key Tests | Gaps |
|----------|----------:|-----------|------|
| Engine Lifecycle | X | engine_start, engine_stop | missing: restart_after_interruption |
| Buffer Safety | X | spsc_write_read | missing: concurrent_stress |
| Route Change | X | ... | ... |
| Pitch Detection | X | ... | ... |
| Metronome | X | ... | ... |
| SoundFont | X | ... | ... |
| MIDI Input | X | ... | ... |

### Test Quality Issues
- [file:line] Issue → Fix

### Missing Tests (Priority Order)
1. [P0] Description → Suggested test
2. [P1] Description → Suggested test

### Summary
X audio tests found, Y passing, Z gaps identified
```
