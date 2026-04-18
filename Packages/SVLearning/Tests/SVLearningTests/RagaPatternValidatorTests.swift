import Testing

@testable import SVLearning

/// Tests for ``RagaPatternValidator`` — validates note sequences against raga
/// aarohan/avarohan patterns.
struct RagaPatternValidatorTests {

    // MARK: - Valid Patterns (No Violations)

    @Test func validAscendingPatternReturnsNoViolations() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Re", "Ga", "Tivra Ma", "Pa", "Dha", "Ni"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.isEmpty)
    }

    @Test func validDescendingPatternReturnsNoViolations() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        let violations = RagaPatternValidator.validatePattern(
            notes: ["Ni", "Dha", "Pa", "Tivra Ma", "Ga", "Re", "Sa"],
            raga: context!,
            direction: .descending
        )

        #expect(violations.isEmpty)
    }

    @Test func partialValidPatternReturnsNoViolations() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        // A subset of the aarohan — should still be valid
        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Re", "Ga"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.isEmpty)
    }

    // MARK: - Out-of-Raga Notes

    @Test func outOfRagaNoteReportsViolation() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        // "Ma" (shuddh) is not in Yaman — only "Tivra Ma" is
        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Re", "Ma", "Pa"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.count == 1)
        #expect(violations[0].noteIndex == 2)
        #expect(violations[0].note == "Ma")
        #expect(violations[0].reason.contains("not in raga Yaman"))
    }

    @Test func multipleOutOfRagaNotesReportAllViolations() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        // "Ma" and "Komal Re" are both not in Yaman
        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Komal Re", "Ma"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.count == 2)
        #expect(violations[0].noteIndex == 1)
        #expect(violations[0].note == "Komal Re")
        #expect(violations[1].noteIndex == 2)
        #expect(violations[1].note == "Ma")
    }

    // MARK: - Unknown Direction

    @Test func unknownDirectionOnlyChecksRagaMembership() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        // All notes are in Yaman's scale, direction is unknown
        let violations = RagaPatternValidator.validatePattern(
            notes: ["Ni", "Sa", "Ga", "Re"],
            raga: context!,
            direction: .unknown
        )

        #expect(violations.isEmpty)
    }

    @Test func unknownDirectionCatchesOutOfRagaNotes() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Ma"],
            raga: context!,
            direction: .unknown
        )

        #expect(violations.count == 1)
        #expect(violations[0].note == "Ma")
    }

    // MARK: - Empty Input

    @Test func emptyNotesArrayReturnsNoViolations() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)

        let violations = RagaPatternValidator.validatePattern(
            notes: [],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.isEmpty)
    }

    // MARK: - Bhairav Raga Tests

    @Test func bhairavAscendingPatternValid() {
        let context = RagaScoringContext.from(ragaName: "Bhairav")
        #expect(context != nil)
        #expect(context?.aarohan != nil)

        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Komal Re", "Ga", "Ma", "Pa", "Komal Dha", "Ni"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.isEmpty)
    }

    @Test func bhairavRejectsShuddhReInAscent() {
        let context = RagaScoringContext.from(ragaName: "Bhairav")
        #expect(context != nil)

        // "Re" (shuddh) is not in Bhairav — only "Komal Re"
        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Re", "Ga"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.count == 1)
        #expect(violations[0].note == "Re")
        #expect(violations[0].reason.contains("not in raga Bhairav"))
    }

    // MARK: - Kafi Raga Tests

    @Test func kafiAscendingPatternValid() {
        let context = RagaScoringContext.from(ragaName: "Kafi")
        #expect(context != nil)
        #expect(context?.aarohan != nil)

        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Re", "Komal Ga", "Ma", "Pa", "Dha", "Komal Ni"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.isEmpty)
    }

    @Test func kafiRejectsShuddhGaInAscent() {
        let context = RagaScoringContext.from(ragaName: "Kafi")
        #expect(context != nil)

        // "Ga" (shuddh) is not in Kafi — only "Komal Ga"
        let violations = RagaPatternValidator.validatePattern(
            notes: ["Sa", "Re", "Ga"],
            raga: context!,
            direction: .ascending
        )

        #expect(violations.count == 1)
        #expect(violations[0].note == "Ga")
    }

    // MARK: - Violation Equality

    @Test func patternViolationEquality() {
        let v1 = RagaPatternValidator.PatternViolation(
            noteIndex: 2, note: "Ma", reason: "Not in raga"
        )
        let v2 = RagaPatternValidator.PatternViolation(
            noteIndex: 2, note: "Ma", reason: "Not in raga"
        )
        let v3 = RagaPatternValidator.PatternViolation(
            noteIndex: 3, note: "Ma", reason: "Not in raga"
        )

        #expect(v1 == v2)
        #expect(v1 != v3)
    }
}

/// Tests for ``RagaScoringContext`` aarohan/avarohan extensions.
struct RagaScoringContextPatternTests {

    @Test func yamanHasAarohanAndAvarohan() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)
        #expect(context?.aarohan != nil)
        #expect(context?.avarohan != nil)
        #expect(context?.aarohan?.count == 7)
        #expect(context?.avarohan?.count == 7)
    }

    @Test func yamanAarohanContainsTivraMa() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context?.aarohan?.contains("Tivra Ma") == true)
        #expect(context?.aarohan?.contains("Ma") == false)
    }

    @Test func bhairavHasPatterns() {
        let context = RagaScoringContext.from(ragaName: "Bhairav")
        #expect(context?.aarohan != nil)
        #expect(context?.avarohan != nil)
        #expect(context?.aarohan?.contains("Komal Re") == true)
        #expect(context?.aarohan?.contains("Komal Dha") == true)
    }

    @Test func kafiHasPatterns() {
        let context = RagaScoringContext.from(ragaName: "Kafi")
        #expect(context?.aarohan != nil)
        #expect(context?.avarohan != nil)
        #expect(context?.aarohan?.contains("Komal Ga") == true)
        #expect(context?.aarohan?.contains("Komal Ni") == true)
    }

    @Test func unknownRagaHasNilPatterns() {
        // Build a context manually for a raga not in the known patterns
        let context = RagaScoringContext(
            ragaName: "CustomRaga",
            allowedSwars: ["Sa", "Re", "Ga", "Pa", "Dha"],
            aarohan: nil,
            avarohan: nil
        )
        #expect(context.aarohan == nil)
        #expect(context.avarohan == nil)
    }

    @Test func manualInitSetsAarohanAndAvarohan() {
        let context = RagaScoringContext(
            ragaName: "TestRaga",
            allowedSwars: ["Sa", "Re", "Ga"],
            aarohan: ["Sa", "Re", "Ga"],
            avarohan: ["Ga", "Re", "Sa"]
        )
        #expect(context.aarohan == ["Sa", "Re", "Ga"])
        #expect(context.avarohan == ["Ga", "Re", "Sa"])
    }
}
