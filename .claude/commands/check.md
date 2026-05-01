# /check — Full quality gate check (lint + format + build + test)

Run the complete quality pipeline that mirrors what CI enforces.

## Steps (sequential — stop on first failure)

### 1. SwiftLint
```
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml 2>&1 | grep -v '\.build/' | grep -v 'DerivedData'
```
- If errors: STOP, report and fix
- If warnings only: report but continue

### 2. swift-format
```
xcrun swift-format lint --configuration .swift-format <all source files>
```
- Report any formatting violations
- Continue regardless

### 3. Build
Use Xcode MCP `BuildProject` or:
```
xcodebuild build -scheme SurVibe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/SurVibe-DD -quiet
```
- If build fails: STOP, report errors

### 4. Tests
```
xcodebuild test -scheme SurVibe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/SurVibe-DD -quiet
```
- Report pass/fail counts

### 5. Summary
```
## Quality Gate Report

| Check        | Status | Details            |
|-------------|--------|--------------------|
| SwiftLint   | PASS   | 0 errors, 0 warns  |
| swift-format| PASS   | All files clean     |
| Build       | PASS   | 0 errors, 0 warns  |
| Tests       | PASS   | 26/26 passed       |

Overall: PASS ✓
```
