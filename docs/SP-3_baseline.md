# SP-3 p95 Latency + Footprint Baseline

Captured 2026-04-19 pre-SP-3a on `feat/sp-3a-scoring-coordinator` branched from `origin/main` @ `6181f7a`.

## Footprint
- `PlayAlongViewModel.swift`: **1,828 lines** · carries `// swiftlint:disable file_length` + `// swiftlint:disable:next type_body_length`.

## Latency contract tests (all green pre-SP-3a)
- `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` — PASS
- `LatencyContractTests.rotationDoesNotRestartAudioEngine` — PASS
- `LatencyContractTests.performanceCriticalViewsDoNotReadThemeEnvironment` — PASS

## SVCore tests
- `swift test --package-path Packages/SVCore` — 93/93 passing.

## Gate for SP-3b/3c/3d
- `PlayAlongViewModel.swift` must only SHRINK after each phase (never grow).
- All latency contract tests must remain green after each phase.
- If `LatencyProbe.lastElapsedMicroseconds` runtime telemetry shifts measurably during manual smoke, investigate before proceeding.

## SP-3 completion signal
- `PlayAlongViewModel.swift` ≤ 200 lines AND `swiftlint:disable` directives deleted AND all latency tests green.

## SP-3b pre-task snapshot (captured on `feat/sp-3b-playback-coordinator`)
- `PlayAlongViewModel.swift`: **1,788 lines** (post-SP-3a baseline).
- `ScoringCoordinator.swift`: 124 lines.
- LatencyContractTests: 3/3 PASS.

## Gate for SP-3b merge
- `PlayAlongViewModel.swift` SHRINKS to **≤ ~1,200 lines** (target: ~600 LOC peeled into PlaybackCoordinator).
- `PlaybackCoordinator.swift` ≈ 600 lines.
- Both `featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` GREEN.
- All 8 PlayAlong suites GREEN.

## SP-3c pre-task snapshot (captured on `feat/sp-3c-chrome-state`)
- `PlayAlongViewModel.swift`: **1,353 lines** (post-SP-3b baseline).
- `PlaybackCoordinator.swift`: 597 lines (unchanged).
- `ScoringCoordinator.swift`: 124 lines (unchanged).
- LatencyContractTests: 3/3 PASS.

## Gate for SP-3c merge
- `PlayAlongViewModel.swift` SHRINKS to **≤ ~1,250 lines** (target: ~150 LOC peeled into PlayAlongChromeState).
- `PlayAlongChromeState.swift` ≈ 150 lines.
- Both `featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` GREEN.
- All 8 PlayAlong suites GREEN. `PlayAlongChromeTests` is the regression guard.

## SP-3d pre-task snapshot (captured on `feat/sp-3d-note-router`)
- `PlayAlongViewModel.swift`: **1,381 lines** (post-SP-3c baseline).
- `PlayAlongChromeState.swift`: 145 lines.
- `PlaybackCoordinator.swift`: 597 lines.
- `ScoringCoordinator.swift`: 124 lines.
- LatencyContractTests: 3/3 PASS.

## Gate for SP-3d merge (umbrella close-out)
- `PlayAlongViewModel.swift` ≤ **200 lines** (target: ~880 LOC peeled into NoteRouter + chrome cleanup).
- `NoteRouter.swift` ≈ 700-900 lines (largest coordinator).
- `PlayAlongChromeState.swift` grows by ~10 lines for `autoHideOverrideSeconds` API (D-SP3d-4).
- `// swiftlint:disable file_length` on VM line 1 DELETED.
- `// swiftlint:disable:next type_body_length` on VM line 38 DELETED.
- Both latency contract tests + all 8 PlayAlong suites GREEN.
- ADR-002 Phase 1/Phase 2 invariants preserved.
- Tags pushed: `sp-3d-note-router` + `sp-3-vm-split-complete` (umbrella).
