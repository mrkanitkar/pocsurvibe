import SwiftUI
import Testing
@testable import SVCore

struct StepTypeColorSystemTests {

    // MARK: - Coverage

    @Test func allStepKindsEnumerated() {
        #expect(LessonStepKind.allCases.count == 5)
    }

    @Test func rawValuesAreStable() {
        #expect(LessonStepKind.intro.rawValue == "intro")
        #expect(LessonStepKind.exercise.rawValue == "exercise")
        #expect(LessonStepKind.listen.rawValue == "listen")
        #expect(LessonStepKind.sing.rawValue == "sing")
        #expect(LessonStepKind.quiz.rawValue == "quiz")
    }

    // MARK: - Value stability

    @Test func introIsBlue() {
        #expect(StepTypeColorSystem.color(for: .intro) == .blue)
    }

    @Test func exerciseIsGreen() {
        #expect(StepTypeColorSystem.color(for: .exercise) == .green)
    }

    @Test func listenIsPurple() {
        #expect(StepTypeColorSystem.color(for: .listen) == .purple)
    }

    @Test func singIsPink() {
        #expect(StepTypeColorSystem.color(for: .sing) == .pink)
    }

    @Test func quizIsOrange() {
        #expect(StepTypeColorSystem.color(for: .quiz) == .orange)
    }

    // MARK: - String-parsing convenience

    @Test func stringParsingLowercases() {
        #expect(LessonStepKind(stepType: "INTRO") == .intro)
        #expect(LessonStepKind(stepType: "Exercise") == .exercise)
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
    }
}
