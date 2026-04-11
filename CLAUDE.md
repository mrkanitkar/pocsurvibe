# SurVibe — Claude Code Rules

> AI-powered piano learning app for Indian users. iOS 26+ only. SwiftUI + SwiftData + AudioKit.
> This file governs ALL code generation, reviews, and refactoring in this project.

---

## IDENTITY

You are the sole developer of SurVibe, an iOS app that teaches piano through Indian classical music (Sargam notation, ragas, gamakas). You write production-quality Swift code that follows Apple's latest best practices. You never guess — if unsure, you say so and research before writing code.

---

## ARCHITECTURE (NON-NEGOTIABLE)

### 8 Swift Packages — One-Way Dependencies

```
SurVibeApp (top-level, imports all 7)
├── SVCore        (foundation — no local deps)
├── SVAudio       (depends on SVCore)
├── SVLearning    (depends on SVCore, SVAudio)
├── SVAI          (depends on SVCore)
├── SVSocial      (depends on SVCore, SVAudio)
├── SVBilling     (depends on SVCore)
└── SVAdvanced    (depends on SVCore, SVAudio, SVAI)
```

**RULES:**
- NEVER create circular dependencies. If SVCore needs something from SVAudio, use a protocol in SVCore and conform in SVAudio.
- Every package has `platforms: [.iOS(.v26)]` in Package.swift.
- Every package has a `Tests/` target with minimum 1 test per public type.
- New files go in the CORRECT package. Ask if unsure.

### External SPM Dependencies

| Package | URL | Min Version | Used By |
|---------|-----|-------------|---------|
| AudioKit | https://github.com/AudioKit/AudioKit | 5.6.0 | SVAudio |
| SoundpipeAudioKit | https://github.com/AudioKit/SoundpipeAudioKit | 5.6.0 | SVAudio (DSP utilities) |
| AudioKit Microtonality | https://github.com/AudioKit/Microtonality | `branch: main` | SVAudio (22 shruti) |
| PostHog iOS | https://github.com/PostHog/posthog-ios | 3.0.0 | SVCore |

**NEVER add a dependency without explicit approval.** Prefer Apple frameworks over third-party.

---

## SWIFT RULES (MANDATORY)

### Deployment Target: iOS 26.0
- NEVER use `#available(iOS X, *)` checks — everything targets iOS 26+.
- NEVER use `if #available` — all APIs from iOS 26 and below are available unconditionally.
- Use Apple Foundation Models framework directly (no version check needed).

### SwiftUI
- **@Observable macro ONLY** — `ObservableObject` and `@Published` are BANNED.
- **No AppDelegate, No SceneDelegate** — use `@main struct SurVibeApp: App { }`.
- Use `@Environment(\.modelContext)` for SwiftData access in views.
- Use `.navigationDestination(for:)` with typed routes, NOT NavigationLink with destination closure.
- Every view that takes data should use `let` properties, not bindings, unless editing.

### SwiftData
- **VersionedSchema is BANNED** — incompatible with CloudKit automatic sync.
- ALL `@Model` fields MUST have explicit default values: `var name: String = ""`.
- ALL relationships MUST be optional.
- Enums stored as `String` rawValue (CloudKit compatibility).
- Arrays and Dictionaries sync as opaque `Transformable` blobs — cannot be queried server-side.
- Schema changes: ADD new fields with defaults ONLY. NEVER delete or rename fields.
- Manual `schemaVersion` integer in UserDefaults (checked on launch).
- ModelContainer configured with: `ModelConfiguration(cloudKitDatabase: .automatic)`.

### CloudKit
- Conflict strategy: additive-only + max-wins (higher value survives).
- XP, scores, play counts: highwater mark (keep higher).
- Achievements, practice entries: append-only (never delete).
- `unlocked` flags: one-way (false→true, never reverts).
- Required entitlements: iCloud (CloudKit), Background Modes (Remote notifications + Audio), Push Notifications.

### Concurrency (Swift 6 Strict)
- Use Swift structured concurrency (`async/await`, `TaskGroup`).
- NEVER use `DispatchQueue.main.async` — use `@MainActor` instead.
- NEVER use completion handlers for new code — use async/await.
- NEVER use `@unchecked Sendable` — use `@MainActor` isolation for mutable shared state.
- Mark all managers, singletons, and view models as `@MainActor`.
- Use `nonisolated private static func` for pure computation (DSP, math, pitch detection).
- NotificationCenter closures: extract `Sendable` values from `Notification.userInfo` BEFORE entering `Task { @MainActor in }` (Notification is not Sendable).
- `@Sendable` annotation on all closures that cross isolation boundaries (mic tap handlers, notification callbacks).

### Error Handling
- NEVER use `try!` or `force-unwrap (!)` in production code.
- Use `do/catch` with meaningful error types.
- Errors that cross package boundaries use protocols defined in SVCore.
- Log errors via `os.Logger` (subsystem: "com.survibe", category: package name).

---

## AUDIO RULES

### Single AVAudioEngine (WWDC 2014/2019)
- ONE `AVAudioEngine` instance via `AudioEngineManager.shared` singleton.
- NEVER create a second engine.
- Nodes: AVAudioInputNode (mic), AVAudioUnitSampler (SoundFont), AVAudioPlayerNode×2 (tanpura, metronome), main mixer.
- Engine starts ONLY when user enters practice mode, NOT at app launch.

### Pitch Detection
- Two implementations behind `PitchDetectorProtocol` (defined in `SVAudio/Pitch/PitchDetector.swift`):
  1. **AudioKitPitchDetector** — autocorrelation via `vDSP_dotpr` + `vDSP_vsmul` (primary).
  2. **YINPitchDetector** — YIN algorithm using `Accelerate/vDSP` (fallback).
- Chord detection uses `LatencyPreset` for user-configurable FFT window sizes:
  - **Ultra Fast**: 1024 samples (~23ms) — fastest response, lower frequency resolution
  - **Fast** (default): 2048 samples (~46ms) — good for C3 and above
  - **Balanced**: 4096 samples (~93ms) — full range, better accuracy
  - **Precise**: 8192 samples (~186ms) — low bass, complex chords
- Melody detection (autocorrelation) uses the engine's fixed 2048-sample buffer.
- Both return `AsyncStream<PitchResult>` (frequency, amplitude, note name, octave, cents offset, confidence).
- Shared frequency-to-note conversion in `SwarUtility.swift` using `Swar.allCases`.
- **Note:** PitchTap from SoundpipeAudioKit conflicts with single-engine pattern; re-evaluate in Sprint 2.

### Audio Session
```swift
// ALWAYS configure before starting engine
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
try session.setMode(.measurement) // accurate pitch detection
try session.setActive(true)
```

### Microphone Permission
- Request in context (first practice attempt), NOT at app launch (Apple HIG).
- Use `AVAudioApplication.requestRecordPermission()`.
- Handle denied state: show inline message + Settings deep link. SoundFont still plays.
- NEVER block the app if mic is denied.

### Haptics
```swift
// CORRECT syntax:
let heavy = UIImpactFeedbackGenerator(style: .heavy)  // sam beats
let light = UIImpactFeedbackGenerator(style: .light)   // other beats
let notification = UINotificationFeedbackGenerator()    // success/error
```

---

## CODING STANDARDS

### File Organization
```
// 1. Imports (alphabetized)
import AudioKit
import Foundation
import SwiftUI

// 2. MARK sections
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Protocol Conformance
```

### Naming
- Types: `PascalCase` — `PitchDetector`, `RiyazEntry`
- Properties/methods: `camelCase` — `currentRang`, `detectPitch()`
- Constants: `camelCase` — `let maxBufferSize = 4096`
- Protocols: noun or adjective — `PitchDetecting`, `Cacheable`
- Boolean properties: `is`/`has`/`can` prefix — `isPlaying`, `hasPermission`
- Sargam/Indian music terms: use standard transliteration — Sa, Re, Ga, Ma, Pa, Dha, Ni (capitalized)

### Documentation (MANDATORY)
Every public type and method MUST have documentation:

```swift
/// Detects pitch from microphone input using autocorrelation via vDSP.
///
/// Uses a configurable buffer size for FFT analysis.
/// Default buffer of 2048 samples provides ~46ms latency.
///
/// - Parameters:
///   - bufferSize: FFT buffer size. Default 2048, user-configurable to 4096.
///   - sampleRate: Audio sample rate. Always 44100 Hz.
/// - Returns: Detected frequency in Hz, or nil if below confidence threshold.
/// - Throws: `AudioError.engineNotRunning` if AVAudioEngine is not started.
func detectPitch(bufferSize: Int = 2048, sampleRate: Double = 44100) async throws -> Double?
```

**Rules:**
- First line: what it does (imperative mood).
- Second paragraph: how it works (implementation details).
- All parameters documented.
- Return value documented.
- Thrown errors documented.
- Internal/private methods: at minimum a one-line `///` comment.

### Accessibility (MANDATORY)
- ALL interactive elements: `accessibilityLabel` + `accessibilityHint`.
- ALL images: `accessibilityLabel` or `.accessibilityHidden(true)` if decorative.
- Note names announced by VoiceOver: "Sa sharp" not "S#".
- `@Environment(\.accessibilityReduceMotion)` guard on ALL animations.
- Dynamic Type for all non-notation text (`.font(.body)` or semantic styles).
- Notation: fixed size + pinch-to-zoom.

---

## TESTING RULES

### Every PR Must Include Tests
- **Unit tests** for all business logic, models, ViewModels.
- **Minimum coverage**: 80% per package, 90% for SVCore.
- Test file naming: `{ClassName}Tests.swift` in the package's `Tests/` directory.

### Test Structure
```swift
import Testing
@testable import SVCore

struct UserProfileTests {
    @Test func defaultValuesAreCorrect() {
        let profile = UserProfile()
        #expect(profile.displayName == "")
        #expect(profile.currentRang == 1)
        #expect(profile.totalXP == 0)
    }

    @Test func xpUsesHighwaterMark() {
        var profile = UserProfile()
        profile.totalXP = 100
        // Simulate sync conflict — lower value should not overwrite
        let syncedXP = 50
        profile.totalXP = max(profile.totalXP, syncedXP)
        #expect(profile.totalXP == 100)
    }
}
```

**Rules:**
- Use Swift Testing framework (`import Testing`, `@Test`, `#expect`), NOT XCTest for new tests.
- XCTest only for UI tests and performance tests.
- Test names describe behavior: `func xpUsesHighwaterMark()` not `func testXP()`.
- One assertion concept per test (multiple `#expect` is fine if testing the same thing).
- Mock external dependencies using protocols defined in SVCore.

### What to Test
- All `@Model` default values and conflict resolution logic.
- All ViewModel state transitions.
- Analytics event names and properties (verify strings match PostHog spec).
- Audio buffer calculations and latency math.
- Permission flows (granted, denied, restricted).
- Edge cases: empty strings, zero values, nil optionals, Date.distantPast.

### What NOT to Test
- SwiftUI view layout (use Xcode previews instead).
- Apple framework internals (AVAudioEngine, CloudKit sync).
- Third-party library internals (AudioKit, PostHog).

---

## LOCALIZATION RULES

### String Catalogs (.xcstrings)
- One `.xcstrings` catalog per package with user-facing strings (NOT centralized).
- Main app target: `SurVibe/Localizable.xcstrings`
- SPM packages: `{Package}/Sources/{Package}/Resources/Localizable.xcstrings`
- `SurVibe/InfoPlist.xcstrings` for privacy strings (NSMicrophoneUsageDescription).

### Localization Patterns
| Context | Pattern |
|---------|---------|
| SwiftUI views (app target) | `Text("Your string")` — auto-extracted |
| SwiftUI views (SPM package) | `Text("Your string", bundle: .module)` |
| Non-SwiftUI (app target) | `String(localized: "key")` |
| Non-SwiftUI (SPM package) | `String(localized: "key", bundle: .module)` |
| Non-localizable display text | `Text(verbatim: value)` |
| Technical/debug strings | Plain string literal (no localization) |

### What NOT to Localize
- Sargam note names: Sa, Re, Ga, Ma, Pa, Dha, Ni (proper nouns across all Indian languages)
- Devanagari labels: सा, रे, ग, म, प, ध, नि
- Western note names: C, D, E, F, G, A, B
- Rang color names: Neel, Hara, Peela, Lal, Sona
- Brand: "SurVibe"
- Analytics events, debug strings, queue labels, logger messages

### Adding a New Language
1. Register ISO 639 code in `knownRegions` (project.pbxproj) — already done for all 22.
2. Add `"xx": { "stringUnit": { "state": "translated", "value": "..." } }` entries in each `.xcstrings` file.
3. No new files, directories, or dependencies needed.

### RTL Support (Urdu, Sindhi, Kashmiri)
- SwiftUI handles RTL automatically when using `.leading`/`.trailing`.
- NEVER use `.left`/`.right` for layout alignment.
- Piano keyboard and music notation MUST be forced LTR: `.environment(\.layoutDirection, .leftToRight)`.

---

## ANALYTICS RULES

### PostHog Events — SVCore.AnalyticsManager ONLY
- ALL analytics go through `AnalyticsManager.track(event:properties:)`.
- NEVER import PostHog directly outside SVCore.
- Event names: `snake_case` — `song_played`, `achievement_earned`.
- Property names: `snake_case` — `frequency_hz`, `latency_ms`.
- Privacy: no IP collection, no device fingerprinting, no IDFA, privacy mode ON.

### Defined Events (AnalyticsEvent enum in SVCore)
- `app_scaffolding_loaded` — fires on every app launch
- `audio_poc_pitch_detected` — fires when pitch detection succeeds
- `cloudkit_sync_completed` — fires when CloudKit sync round-trips
- `tab_selected` — fires on tab navigation (property: `tab`)
- `session_started` — fires when practice session begins
- `session_ended` — fires when practice session ends

---

## DESIGN SYSTEM — RANG COLORS

| Level | Name | Hex | WCAG AA | Use |
|-------|------|-----|---------|-----|
| 1 | Neel | #3F51B5 | 4.6:1 ✓ | Beginner |
| 2 | Hara | #388E3C | 4.5:1 ✓ | Developing |
| 3 | Peela | #F9A825 | 3.1:1 Large only | Intermediate |
| 4 | Lal | #D32F2F | 5.3:1 ✓ | Advanced |
| 5 | Sona | #FFB300 | 3.0:1 Large only | Master |
| — | Peela Dark | #C17900 | 4.5:1 ✓ | Body text variant |
| — | Sona Dark | #B87700 | 4.5:1 ✓ | Body text variant |

**Rules:**
- Peela and Sona: ONLY for backgrounds, large text (18pt+), decorative, icons with labels.
- Body text on light backgrounds: use Peela Dark / Sona Dark.
- ALL colors defined in `SVCore/Theme/RangColorSystem.swift` with `Color` extensions in `SVCore/Extensions/Color+Rang.swift`.
- Dark mode: provide all variants (Asset Catalog with light/dark appearances).

---

## LINTING & ENFORCEMENT

### Build-Time Enforcement
- **Swift 6 language mode** — SPM packages enforce strict concurrency via `swift-tools-version: 6.2`
- **App target**: `SWIFT_VERSION = 5.0` in pbxproj, with `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6 concurrency semantics via approachable mode)
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`** recommended for Release configuration — no warnings ship to users

### Two Formatting/Lint Tools (Both Required)
1. **swift-format** (Xcode toolchain: `xcrun swift-format`) — code formatting. Config: `.swift-format`.
2. **SwiftLint** (Homebrew: `/opt/homebrew/bin/swiftlint`) — linting, safety rules. Config: `.swiftlint.yml`.

### Pre-Commit Git Hook (Active)
The `.git/hooks/pre-commit` hook runs automatically on every commit:
- SwiftLint on staged `.swift` files — **errors block the commit**
- swift-format lint — warnings only (non-blocking)

### Running Manually
```bash
# Lint all project sources
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml

# Format a file in-place
xcrun swift-format format --in-place --configuration .swift-format <file>

# Check formatting without modifying
xcrun swift-format lint --configuration .swift-format <file>
```

### SwiftLint Architecture Rules (severity: error)
- `no_observable_object` — blocks `ObservableObject/@Published/@ObservedObject/@StateObject`
- `no_versioned_schema` — blocks `VersionedSchema/SchemaMigrationPlan`

---

## CI/CD — XCODE CLOUD

### Workflows
| Workflow | Trigger | Actions |
|----------|---------|---------|
| Build Check | Every push to main + PRs | xcodebuild, swift-format lint, SwiftLint |
| Test Suite | Nightly + PR merge | Unit tests (7 packages + app target) |
| TestFlight | Tag push (v0.x.x) | Archive + upload to TestFlight |

### ci_post_clone.sh
The CI script at `ci_scripts/ci_post_clone.sh` is **blocking** (`set -euo pipefail`):
1. Resolves SPM dependencies
2. Runs SwiftLint with `--strict` — **lint errors fail the build**
3. Runs swift-format lint — reports violations (non-blocking for now)

---

## COMMIT RULES

### Format
```
<type>(<package>): <description>

<body — what and why>

<footer — breaking changes, issue refs>
```

### Types
- `feat(SVAudio):` — new feature
- `fix(SVCore):` — bug fix
- `refactor(SVLearning):` — code restructuring, no behavior change
- `test(SVAudio):` — adding/updating tests
- `docs(SVCore):` — documentation only
- `chore:` — build, CI, dependencies

### Rules
- Subject line: imperative mood, max 72 chars, no period.
- Body: explain WHY, not just what.
- One logical change per commit.
- Tests included in same commit as the code they test.
- NEVER commit secrets, API keys, or .env files.

---

## TASK ROUTINE (Every Code Change)

Before writing any code, follow this checklist:

### 1. PLAN
- [ ] Identify which package(s) this change belongs to.
- [ ] Check dependency direction — no circular imports.
- [ ] Confirm iOS 26+ only (no #available).

### 2. IMPLEMENT
- [ ] Write code following all rules above.
- [ ] Add `///` documentation to all public types and methods.
- [ ] Add `accessibilityLabel` to all interactive elements.
- [ ] Use `@Observable`, NOT ObservableObject.
- [ ] Use `async/await`, NOT completion handlers.
- [ ] Use `@MainActor`, NOT DispatchQueue.main.

### 3. TEST
- [ ] Write tests using Swift Testing framework.
- [ ] Test happy path + edge cases + error cases.
- [ ] Run: `swift test` in the package directory.
- [ ] Verify no SwiftLint errors.

### 4. VERIFY
- [ ] `xcodebuild clean build` succeeds.
- [ ] All existing tests still pass.
- [ ] VoiceOver audit on any new UI.
- [ ] No new compiler warnings.

### 5. COMMIT
- [ ] Stage only relevant files.
- [ ] Write commit message following format above.
- [ ] Push and verify Xcode Cloud build is green.

---

## BANNED PATTERNS (Will Be Rejected in Review)

| Pattern | Why | Use Instead |
|---------|-----|-------------|
| `ObservableObject` / `@Published` | Legacy | `@Observable` macro |
| `VersionedSchema` | Breaks CloudKit | Manual schema versioning |
| `AppDelegate` / `SceneDelegate` | Legacy | `@main App` |
| `DispatchQueue.main.async` | Legacy | `@MainActor` |
| `try!` / `force unwrap (!)` | Crashes | `do/catch`, optional binding |
| `#available(iOS X, *)` | Unnecessary | iOS 26 minimum |
| Circular package imports | Breaks architecture | Protocols in SVCore |
| Direct PostHog import (outside SVCore) | Breaks analytics layer | `AnalyticsManager.track()` |
| `AUSampler` | Legacy API | `AVAudioUnitSampler` |
| Multiple AVAudioEngine instances | Apple anti-pattern | `AudioEngineManager.shared` |
| Completion handlers (new code) | Legacy | `async/await` |
| String-based notification names | Fragile | Typed protocols or async streams |

---

## APP STRUCTURE

### 4-Tab Navigation
| Tab | View | Icon | Purpose |
|-----|------|------|---------|
| Learn | `LearnTab` | `book.fill` | Lessons, sargam notation, guided learning |
| Practice | `PracticeTab` | `music.note` | Free practice with pitch detection + tanpura |
| Songs | `SongsTab` | `music.note.list` | Song library, play-along, progress tracking |
| Profile | `ProfileTab` | `person.fill` | XP, achievements, rang level, settings |

### @Model Classes (Main App Target)
SwiftData models live in `SurVibe/Models/` (NOT in SVCore) because CloudKit sync requires models + container in the same module. Packages reference model shapes via protocols in `SVCore/Models/`.

| Model | Purpose | Key Fields |
|-------|---------|------------|
| `UserProfile` | Player identity, XP, rang level | `displayName`, `totalXP`, `currentRang` |
| `RiyazEntry` | Daily practice log (additive-only) | `date`, `durationMinutes`, `notes` |
| `Achievement` | Earned badges (append-only) | `type`, `earnedDate`, `isUnlocked` |
| `SongProgress` | Per-song scores (max-wins) | `songId`, `bestScore`, `timesPlayed`, `isCompleted` |
| `LessonProgress` | Per-lesson completion (one-way flag) | `lessonId`, `isCompleted`, `completedDate` |
| `SubscriptionState` | StoreKit 2 local cache | `tier`, `expirationDate`, `isActive` |

### Swar (Note) System
The `Swar` enum in `SVAudio/Models/Note.swift` defines the 12 notes of Indian classical music:

| Swar | Raw Value | MIDI Offset | Western Equivalent |
|------|-----------|-------------|-------------------|
| Sa | "Sa" | 0 | C (tonic) |
| Komal Re | "Komal Re" | 1 | Db |
| Re | "Re" | 2 | D |
| Komal Ga | "Komal Ga" | 3 | Eb |
| Ga | "Ga" | 4 | E |
| Ma | "Ma" | 5 | F |
| Tivra Ma | "Tivra Ma" | 6 | F# |
| Pa | "Pa" | 7 | G |
| Komal Dha | "Komal Dha" | 8 | Ab |
| Dha | "Dha" | 9 | A |
| Komal Ni | "Komal Ni" | 10 | Bb |
| Ni | "Ni" | 11 | B |

- Frequency calculation: `frequency(octave:referencePitch:)` — defaults to octave 4, A4 = 440 Hz.
- Sa is relative to the performer's chosen pitch (not fixed to C).

### Playback
- **TanpuraPlayer** — looped drone using `AVAudioPCMBuffer` with `.loops` option. Provides tonic reference (Sa-Pa drone).
- **MetronomePlayer** — pre-loaded click buffer with sample-accurate `AVAudioTime` scheduling. A look-ahead loop pre-schedules 4 beats on the audio timeline, eliminating wall-clock jitter.
- **SoundFontManager** — `AVAudioUnitSampler` with `loadSoundBankInstrument(at:program:bankMSB:bankLSB:)`. Piano SoundFont for note playback.

---

## DEFERRED ITEMS

Deferred items from the Sprint 0 architect review are tracked in `docs/Sprint0_Gap_Report.md` (source of truth). Do NOT duplicate tracking here.

---

## INDIAN MUSIC CONTEXT

SurVibe teaches piano through Indian classical music. Key terminology:
- **Sargam**: Indian notation system — Sa Re Ga Ma Pa Dha Ni (equivalent to Do Re Mi...)
- **Raga**: melodic framework with specific ascending/descending note patterns
- **Taal**: rhythmic cycle (e.g., Teentaal = 16 beats)
- **Riyaz**: daily practice/sadhana
- **Rang**: color — used as the gamification level system
- **Shruti**: microtonal intervals (22 per octave vs Western 12)
- **Gamaka**: ornamental oscillation on a note
- **Meend**: glide between notes
- **Tanpura**: drone instrument providing tonic reference
- **Sa**: the tonic note (equivalent to "Do", but relative to performer's pitch)

When generating UI text, use these Hindi/Urdu music terms naturally. The app's personality is warm, encouraging, and culturally authentic.

---

## SKILLS & SLASH COMMANDS

### Project Slash Commands (`.claude/commands/`)

These are SurVibe-specific skills. **Invoke the relevant command after every code change.**

| Command | When to Use | File |
|---------|------------|------|
| `/review` | After ANY `.swift` file change — checks architecture, concurrency, data model rules | `review.md` |
| `/audio-review` | After ANY change to `SVAudio/`, `Playback/`, `Practice/` — audio thread safety, latency budget, single engine rule | `audio-review.md` |
| `/latency-check` | Before release or after audio config changes — verifies all 6 audio paths vs 3-10ms target | `latency-check.md` |
| `/audio-test` | After audio code changes — audits test coverage for engine lifecycle, buffers, pitch, MIDI, metronome | `audio-test.md` |
| `/check` | Before every commit — runs lint + format + build + test | `check.md` |
| `/test` | After code changes — builds and runs full test suite | `test.md` |
| `/lint` | Quick lint pass — SwiftLint on changed files | `lint.md` |
| `/format` | Quick format pass — swift-format on changed files | `format.md` |

### Installed Plugin Skills (Auto-Available)

**xclaude-plugin (iOS development):**
- `xclaude-plugin:accessibility-testing` — WCAG compliance, VoiceOver testing, contrast ratios. **Use after ANY UI change** (CLAUDE.md mandates accessibility on all elements)
- `xclaude-plugin:performance-profiling` — Instruments profiling: Time Profiler, Allocations, Leaks, Energy. **Use for audio latency measurement + pre-release**
- `xclaude-plugin:ios-testing-patterns` — XCTest/XCUITest patterns, flaky test detection, CI integration. **Use when writing tests**
- `xclaude-plugin:xcode-workflows` — Build system, scheme config, xcodebuild operations. **Use for build/test**
- `xclaude-plugin:crash-debugging` — Crash log analysis, symbolication, stack traces. **Use when debugging crashes**
- `xclaude-plugin:simulator-workflows` — Simulator management, device lifecycle. **Use for testing**
- `xclaude-plugin:ui-automation-workflows` — Accessibility-first UI automation via IDB. **Use for E2E tests**
- `xclaude-plugin:state-management` — Cache management, token optimization. **Use for large operations**

**superpowers (workflow):**
- `superpowers:test-driven-development` — Write tests BEFORE implementation. **Use for all new features**
- `superpowers:systematic-debugging` — Root cause analysis before fixing. **Use for all bug fixes**
- `superpowers:verification-before-completion` — Verify with evidence before claiming done. **Use before every completion claim**
- `superpowers:brainstorming` — Explore intent and requirements before building. **Use before new features**
- `superpowers:writing-plans` — Create implementation plans from specs. **Use for multi-step tasks**
- `superpowers:executing-plans` — Execute written plans with review checkpoints. **Use for remediation phases**
- `superpowers:requesting-code-review` — Review work against requirements. **Use after major features**
- `superpowers:dispatching-parallel-agents` — Run independent tasks concurrently. **Use for parallel work**
- `superpowers:finishing-a-development-branch` — Guide merge/PR decisions. **Use after completing features**

**Other:**
- `context7` (MCP) — Fetch current documentation for any library/framework. **Use instead of web search for docs**
- `sourcekit-lsp` — Swift LSP for code intelligence (autocomplete, go-to-definition)
- `feature-dev` agents — `code-explorer`, `code-reviewer`, `code-architect` for deep codebase analysis

### Mandatory Skill Usage

| Trigger | Required Skill |
|---------|---------------|
| Changing ANY `.swift` file | `/review` |
| Changing audio/playback/practice code | `/audio-review` + `/audio-test` |
| Before ANY release build | `/latency-check` + `/check` |
| Before claiming task complete | `superpowers:verification-before-completion` |
| Implementing new feature | `superpowers:brainstorming` → `superpowers:test-driven-development` |
| Fixing a bug | `superpowers:systematic-debugging` |
| After UI changes | `xclaude-plugin:accessibility-testing` |
| Building E2E tests | `xclaude-plugin:ios-testing-patterns` + `xclaude-plugin:ui-automation-workflows` |

---

## REFERENCE DOCUMENTS

These documents in `docs/` contain the full architectural decisions. Consult them when making significant changes:

### Primary References
- `SurVibe_Software_Architecture_v1.docx` — full technical architecture (25 decisions)
- `SurVibe_Design_Thinking_v5_GapAnalysis.docx` — product strategy, personas, features
- `SurVibe_Sprint0_Implementation.docx` — Sprint 0 day-by-day plan with quality gates
- `Sprint0_Gap_Report.md` — architect review: all fixes applied, deferred items listed
- `SurVibe_Dependencies_Report.docx` — external dependencies and costs
- `missinglink.md` — **full audit gap report** (207 gaps, 43-item remediation plan, skills mapping)

### Architecture Decision Records
- `SurVibe_Hostile_Review_Round2.docx` — adversarial architecture review
- `SurVibe_Architecture_Pattern_Comparison.docx` — pattern evaluation
- `SurVibe_Architecture_Q2_Q3_Comparison.docx` — SwiftData vs Core Data, sync strategy
- `SurVibe_Architecture_Q4_Q5_Q6_Comparison.docx` — audio, pitch detection, permissions
- `SurVibe_Architecture_Q13_CICD.docx` — CI/CD pipeline decisions
- `SurVibe_Architecture_Q15_Q22_Comparison.docx` — gamification, onboarding

---

*Last updated: April 2026 | Version 3.2 (Skills Audit)*
*Covers: 25 architecture decisions, 21 architect review fixes, enforcement pipeline, app structure, deferred items, skills mapping*
