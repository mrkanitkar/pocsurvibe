# SurVibe — Claude Code Rules

> AI-powered piano learning app for Indian users. iOS 26+ only. SwiftUI + SwiftData + AudioKit.
> This file governs ALL code generation, reviews, and refactoring in this project.
> Domain-specific rules are in `.claude/rules/` and load automatically when matching files are opened.

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
- Every package has `platforms: [.iOS(.v26)]` in Package.swift. SVCore, SVAI, and SVBilling also include `.macOS(.v15)` for shared logic reuse.
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

### Deployment Target: iOS 26.2
- No `#available` or `if #available` checks — everything targets iOS 26+ unconditionally (see Banned Patterns).
- Use Apple Foundation Models framework directly (no version check needed).
- Always prefer the NEWEST API available for iOS 26.2. If an API predates this target, a newer replacement probably exists — flag it instead of using the old one.

### API Verification (Cupertino MCP) — MANDATORY
- Before writing code that uses ANY Apple framework API (SwiftUI, SwiftData, AVFoundation, CoreMIDI, StoreKit, CloudKit, CoreML, Foundation Models, …), query the `cupertino` MCP to confirm the symbol exists, its exact signature, and its availability on iOS 26.2.
- Do NOT write framework code from memory — model knowledge drifts toward deprecated UIKit / `ObservableObject` / StoreKit 1 / completion-handler patterns.
- If `cupertino` returns no result, say so and ask rather than guessing.
- When `cupertino` and the live SDK (Xcode build) disagree, trust the SDK — it matches what actually compiles here.

### SwiftUI
- Use `@Environment(\.modelContext)` for SwiftData access in views.
- Use `.navigationDestination(for:)` with typed routes, NOT NavigationLink with destination closure.
- Every view that takes data should use `let` properties, not bindings, unless editing.
- Use `@State private var model = MyModel()` to own `@Observable` instances in views (NOT `@StateObject`).
- Use `@Bindable var model` for `@Observable` objects passed to child views that need two-way binding.
- Inside `@Observable` classes, mark `@AppStorage` and `@SceneStorage` with `@ObservationIgnored`.
- Use `.glassEffect(.regular)` for cards, tab bars, and navigation surfaces on iOS 26 (Liquid Glass).

### Concurrency (Swift 6 Strict)
- Use Swift structured concurrency (`async/await`, `TaskGroup`).
- NEVER use completion handlers for new code — use async/await.
- Avoid `@unchecked Sendable` — prefer `Mutex<State>` or `@MainActor`. **Allowed:** NSObject delegates (e.g., `MusicXMLParserDelegate`), CoreMIDI interop, test doubles.
- Mark all managers, singletons, and view models as `@MainActor`. **Exception:** `MIDIInputManager` uses `OSAllocatedUnfairLock (per AUD-033)` instead of `@MainActor` because CoreMIDI callbacks arrive on arbitrary threads.
- Use `nonisolated private static func` for pure computation (DSP, math, pitch detection).
- Use `nonisolated(unsafe)` ONLY with external synchronization (NSLock/Mutex). ALWAYS add a `///` comment explaining the safety invariant. Prefer consolidating mutable state into `Mutex<State>` structs to reduce `nonisolated(unsafe)` count.
- NotificationCenter closures: extract `Sendable` values from `Notification.userInfo` BEFORE entering `Task { @MainActor in }` (Notification is not Sendable).
- `@Sendable` annotation on all closures that cross isolation boundaries (mic tap handlers, notification callbacks).
- Consider `sending` parameter annotation for cross-isolation transfer of non-Sendable values (Swift 6+).

### Error Handling
- No `try!` or `force unwrap (!)` in production code (see Banned Patterns).
- Use `do/catch` with meaningful error types.
- Errors that cross package boundaries use protocols defined in SVCore.
- Log errors via `os.Logger` (subsystem: "com.survibe", category: package name).

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

## STORAGE & BUILD HYGIENE (MANDATORY)

> SurVibe builds can balloon to **100GB/hour** without these rules. Each `xcodebuild` without `-derivedDataPath` writes a fresh multi-GB folder; subagent worktrees + multiple sessions multiply this fast. Treat disk like a shared resource.

### The Single Shared Path

**ALL `xcodebuild` invocations MUST use:**

```
-derivedDataPath /private/tmp/SurVibe-DD
```

This applies to: slash commands (`/test`, `/check`, `/audio-test`), subagent runs, ad-hoc shell builds, CI parity checks. Do NOT invent new paths like `/private/tmp/svtest-xyz/` or `~/Documents/.../dd`. One path, reused, incrementally rebuilt.

**Why:** Reusing a single DerivedData lets Xcode incrementally rebuild — typically <1GB churn per build instead of a fresh 4-6GB tree per invocation.

### Hard Rules

| Rule | Why |
|------|-----|
| Never run `xcodebuild` without `-derivedDataPath /private/tmp/SurVibe-DD` | Stops the per-invocation multi-GB sprawl |
| Never write logs to `/private/tmp/log*.txt` | Use stdout, or write to a single named file you delete after |
| Never create ad-hoc DerivedData dirs (`/tmp/svtest`, `/tmp/SVAudio-dd`, etc.) | Use the shared path |
| Never store test app containers or `.xcappdata` in `/tmp` long-term | Move to `docs/` or delete |
| When dispatching subagents that build, instruct them to use the same `-derivedDataPath` | Otherwise each worktree gets its own 4GB cache |
| Run `/clean` before any session where disk is <30GB free | Reclaims space, doesn't break builds |
| Use `xcrun simctl delete unavailable` after Xcode upgrades | Old simulator runtimes pile up to 10+ GB |
| Use `git worktree prune` after subagent-driven dev sessions end | Removes orphaned worktree metadata |

### Subagent Builds

When dispatching subagents that need to build/test:
- **Pass `-derivedDataPath /private/tmp/SurVibe-DD` in their prompt** if they will run `xcodebuild`
- Prefer `mcp__XcodeBuildMCP__build_sim` / `test_sim` tools — they reuse derived data automatically
- If using `isolation: "worktree"`, prefer `swift test --package-path Packages/<X>` over full app builds (no DerivedData explosion)

### Forbidden Storage Patterns

| Pattern | Use Instead |
|---------|------------|
| `xcodebuild ... ` without `-derivedDataPath` | Always include `-derivedDataPath /private/tmp/SurVibe-DD` |
| New random `/tmp/<dd-name>/` folders | The single shared path |
| Saving long-lived logs to `/private/tmp/` | Stream to stdout; if persistence needed, use `docs/` (gitignored) |
| Manually `rm -rf` simulator devices | `xcrun simctl delete <udid>` so Xcode stays in sync |
| Force-deleting active git worktrees | `git worktree remove <path>` (validates first) |

### Periodic Maintenance

Run `/clean` weekly (or when free disk <30GB). It will:
1. Wipe `/private/tmp/SurVibe-DD` and any legacy ad-hoc DerivedData
2. Remove `~/Library/Developer/Xcode/DerivedData/SurVibe-*`
3. Run `xcrun simctl delete unavailable`
4. Prune stale git worktrees
5. Report before/after disk usage

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

**Invoke the relevant command after every code change.**

| Command | When to Use |
|---------|------------|
| `/review` | After ANY `.swift` file change |
| `/audio-review` | After ANY change to `SVAudio/`, `Playback/`, `Practice/` |
| `/latency-check` | Before release or after audio config changes |
| `/audio-test` | After audio code changes |
| `/check` | Before every commit — lint + format + build + test |
| `/test` | After code changes — builds and runs full test suite |
| `/lint` | Quick lint pass — SwiftLint on changed files |
| `/format` | Quick format pass — swift-format on changed files |
| `/clean` | Reclaim disk — wipe stale DerivedData, sims, worktrees |

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

*Last updated: April 2026 | Version 4.0 (Split into .claude/rules/)*
*Covers: 25 architecture decisions, 21 architect review fixes, enforcement pipeline, deferred items, skills mapping*
