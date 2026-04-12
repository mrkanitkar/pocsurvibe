---
paths:
  - "ci_scripts/**"
---

# CI/CD — Xcode Cloud

## Workflows

| Workflow | Trigger | Actions |
|----------|---------|---------|
| Build Check | Every push to main + PRs | xcodebuild, swift-format lint, SwiftLint |
| Test Suite | Nightly + PR merge | Unit tests (7 packages + app target) |
| TestFlight | Tag push (v0.x.x) | Archive + upload to TestFlight |

## ci_post_clone.sh
The CI script at `ci_scripts/ci_post_clone.sh` is **blocking** (`set -euo pipefail`):
1. Resolves SPM dependencies
2. Runs SwiftLint with `--strict` — **lint errors fail the build**
3. Runs swift-format lint — reports violations (non-blocking for now)
