import SwiftUI
import Testing
@testable import SVCore

struct StepTypeColorSystemTests {

    // MARK: - Coverage (7 kinds — matches seed-lessons.json production content)

    @Test func allStepKindsEnumerated() {
        #expect(LessonStepKind.allCases.count == 7)
    }

    @Test func rawValuesAreStable() {
        #expect(LessonStepKind.intro.rawValue == "intro")
        #expect(LessonStepKind.read.rawValue == "read")
        #expect(LessonStepKind.listen.rawValue == "listen")
        #expect(LessonStepKind.exercise.rawValue == "exercise")
        #expect(LessonStepKind.practice.rawValue == "practice")
        #expect(LessonStepKind.sing.rawValue == "sing")
        #expect(LessonStepKind.quiz.rawValue == "quiz")
    }

    // MARK: - Value stability (Option C — 5 colors mapping 7 kinds)

    @Test func introIsBlue() {
        #expect(StepTypeColorSystem.color(for: .intro) == .blue)
    }

    @Test func readSharesIntroBlue() {
        // Pedagogical grouping: intro + read are both receptive/informational text.
        #expect(StepTypeColorSystem.color(for: .read) == .blue)
    }

    @Test func listenIsPurple() {
        #expect(StepTypeColorSystem.color(for: .listen) == .purple)
    }

    @Test func exerciseIsGreen() {
        #expect(StepTypeColorSystem.color(for: .exercise) == .green)
    }

    @Test func practiceSharesExerciseGreen() {
        // Pedagogical grouping: exercise + practice are both active/kinesthetic.
        #expect(StepTypeColorSystem.color(for: .practice) == .green)
    }

    @Test func singIsPink() {
        #expect(StepTypeColorSystem.color(for: .sing) == .pink)
    }

    @Test func quizIsYellow() {
        // Matches the existing helper convention; evaluation is its own bucket.
        #expect(StepTypeColorSystem.color(for: .quiz) == .yellow)
    }

    // MARK: - String-parsing convenience

    @Test func stringParsingLowercases() {
        #expect(LessonStepKind(stepType: "INTRO") == .intro)
        #expect(LessonStepKind(stepType: "Read") == .read)
        #expect(LessonStepKind(stepType: "PRACTICE") == .practice)
        #expect(LessonStepKind(stepType: "sing") == .sing)
    }

    @Test func unknownStepTypeReturnsNil() {
        #expect(LessonStepKind(stepType: "bogus") == nil)
    }

    @Test func colorForStepTypeFallsBackOnUnknown() {
        let color = StepTypeColorSystem.color(forStepType: "bogus", fallback: .gray)
        #expect(color == .gray)
    }

    @Test func colorForStepTypeRoutesKnown() {
        #expect(StepTypeColorSystem.color(forStepType: "sing") == .pink)
        #expect(StepTypeColorSystem.color(forStepType: "read") == .blue)
        #expect(StepTypeColorSystem.color(forStepType: "practice") == .green)
    }
}
