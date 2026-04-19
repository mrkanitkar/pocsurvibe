import Foundation
import SwiftData
import Testing

@testable import SurVibe

/// Tests for LessonPlayerViewModel step gating and navigation logic.
///
/// Verifies that gate callbacks from lesson step views (listen, sing,
/// exercise, quiz) correctly unlock gates, and that navigation respects
/// gate status. Uses an in-memory ModelContainer for LessonProgressManager.
/// Serialized + shared container — see `SwiftDataTestContainer.swift`.
@Suite("LessonPlayerViewModel Tests", .serialized)
@MainActor
struct LessonPlayerViewModelTests {

    // MARK: - Helpers

    /// Creates a Lesson with the given steps encoded as JSON.
    private func makeLesson(steps: [LessonStep]) -> Lesson {
        let lesson = Lesson(lessonId: "test-lesson", title: "Test Lesson")
        if let data = try? JSONEncoder().encode(steps) {
            lesson.stepsData = data
        }
        return lesson
    }

    /// Creates a ViewModel from a lesson and a fresh shared-container context.
    private func makeVM(steps: [LessonStep]) throws -> LessonPlayerViewModel {
        let context = try SwiftDataTestContainer.freshContext()
        let manager = LessonProgressManager(modelContext: context)
        let lesson = makeLesson(steps: steps)
        let vm = LessonPlayerViewModel(lesson: lesson, progressManager: manager)
        vm.onAppear()
        return vm
    }

    // MARK: - Gate Default Tests

    @Test("Intro step is always unlocked")
    func introStepUnlocked() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "intro", content: "Welcome"),
        ])
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("Read step is always unlocked")
    func readStepUnlocked() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "read", content: "Read this"),
        ])
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("Listen step starts locked")
    func listenStepStartsLocked() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "listen", content: "Listen here"),
        ])
        #expect(vm.gateStatus == .locked(reason: "Listen to the audio to continue"))
    }

    @Test("Sing step starts locked")
    func singStepStartsLocked() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "sing", content: "Sing along"),
        ])
        #expect(vm.gateStatus == .locked(reason: "Sing along to continue"))
    }

    @Test("Exercise step starts locked")
    func exerciseStepStartsLocked() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "exercise", content: "Practice"),
        ])
        #expect(vm.gateStatus == .locked(reason: "Complete the exercise to continue"))
    }

    @Test("Quiz step starts locked")
    func quizStepStartsLocked() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "quiz", content: "[]"),
        ])
        #expect(vm.gateStatus == .locked(reason: "Answer all questions to continue"))
    }

    // MARK: - Gate Callback Tests

    @Test("listenCompleted unlocks gate")
    func listenCompletedUnlocks() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "listen", content: "Listen"),
        ])
        #expect(vm.gateStatus != .unlocked)

        vm.listenCompleted()
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("singCompleted with accuracy >= 0.60 unlocks gate")
    func singCompletedAboveThreshold() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "sing", content: "Sing"),
        ])
        vm.singCompleted(accuracy: 0.70)
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("singCompleted with accuracy < 0.60 keeps gate locked")
    func singCompletedBelowThreshold() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "sing", content: "Sing"),
        ])
        vm.singCompleted(accuracy: 0.50)
        #expect(vm.gateStatus != .unlocked)
    }

    @Test("singCompleted at exactly 0.60 unlocks gate")
    func singCompletedAtBoundary() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "sing", content: "Sing"),
        ])
        vm.singCompleted(accuracy: 0.60)
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("singManualAdvance unlocks gate regardless of accuracy")
    func singManualAdvanceUnlocks() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "sing", content: "Sing"),
        ])
        vm.singManualAdvance()
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("exerciseCompleted unlocks gate")
    func exerciseCompletedUnlocks() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "exercise", content: "Drill"),
        ])
        vm.exerciseCompleted()
        #expect(vm.gateStatus == .unlocked)
    }

    @Test("quizCompleted unlocks gate and records score")
    func quizCompletedUnlocksAndRecordsScore() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "quiz", content: "[]"),
        ])
        vm.quizCompleted(score: 0.80)
        #expect(vm.gateStatus == .unlocked)
        #expect(vm.quizScore == 0.80)
    }

    @Test("quizCompleted uses high-water mark")
    func quizScoreHighWaterMark() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "quiz", content: "[]"),
        ])
        vm.quizCompleted(score: 0.80)
        #expect(vm.quizScore == 0.80)

        vm.quizCompleted(score: 0.60)
        #expect(vm.quizScore == 0.80, "Lower score should not overwrite")

        vm.quizCompleted(score: 0.95)
        #expect(vm.quizScore == 0.95, "Higher score should overwrite")
    }

    // MARK: - Navigation Tests

    @Test("canGoBack is false on first step")
    func cannotGoBackOnFirstStep() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "intro", content: "First"),
            LessonStep(stepType: "read", content: "Second"),
        ])
        #expect(vm.canGoBack == false)
    }

    @Test("canGoNext requires unlocked gate")
    func canGoNextRequiresUnlockedGate() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "listen", content: "Listen"),
            LessonStep(stepType: "read", content: "Read"),
        ])
        #expect(vm.canGoNext == false)

        vm.listenCompleted()
        #expect(vm.canGoNext == true)
    }

    @Test("goToNextStep advances step index")
    func goToNextStepAdvances() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "intro", content: "First"),
            LessonStep(stepType: "read", content: "Second"),
        ])
        #expect(vm.currentStepIndex == 0)

        vm.goToNextStep()
        #expect(vm.currentStepIndex == 1)
    }

    @Test("goToNextStep on last step completes lesson")
    func lastStepCompletesLesson() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "intro", content: "Only step"),
        ])
        vm.goToNextStep()
        #expect(vm.phase == .completed)
    }

    @Test("Empty lesson immediately completes")
    func emptyLessonCompletes() throws {
        let vm = try makeVM(steps: [])
        #expect(vm.phase == .completed)
    }

    @Test("progressFraction increases as steps complete")
    func progressFractionUpdates() throws {
        let vm = try makeVM(steps: [
            LessonStep(stepType: "intro", content: "1"),
            LessonStep(stepType: "intro", content: "2"),
            LessonStep(stepType: "intro", content: "3"),
            LessonStep(stepType: "intro", content: "4"),
        ])
        #expect(vm.progressFraction == 0.0)

        vm.goToNextStep()
        #expect(vm.progressFraction == 0.25)
    }
}
