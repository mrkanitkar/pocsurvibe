# /test — Build and run the SurVibe test suite

Build the project and run all tests with structured output.

## Steps

**STORAGE:** All `xcodebuild` calls below use `-derivedDataPath /private/tmp/SurVibe-DD` (shared, reused). NEVER omit this flag — Xcode otherwise creates a new multi-GB DerivedData folder per invocation.

1. First build the project to catch compile errors:
   - Use Xcode MCP `BuildProject` if available
   - Or: `xcodebuild build -scheme SurVibe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/SurVibe-DD -quiet`

2. If the build fails, report errors and stop. Do NOT proceed to tests.

3. Run the full test suite:
   ```
   xcodebuild test -scheme SurVibe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/SurVibe-DD -quiet 2>&1
   ```

4. Parse the output and report:
   - Total tests run / passed / failed
   - Failed test details with file:line references
   - Test suite timing

5. If tests fail, read the failing test file and the code it tests, then suggest fixes.

## Options

- `/test unit` — Run only unit tests (skip UI tests):
  Filter to test suites not containing "UITest"

- `/test <TestClass>` — Run a specific test class:
  ```
  xcodebuild test -scheme SurVibe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/SurVibe-DD -only-testing "SurVibeTests/<TestClass>" -quiet
  ```

- `/test quick` — Use Xcode MCP BuildProject only (no test execution, just compile check)

## Notes
- Simulator: iPhone 17 Pro with iOS 26
- All `@MainActor`-isolated tests need `@MainActor` annotation on the test function
- SwiftData tests use in-memory `ModelConfiguration`
