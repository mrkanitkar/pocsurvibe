import SVCore
import SwiftData
import SwiftUI

/// Full-screen step-by-step lesson experience driven by `LessonPlayerViewModel`.
///
/// Presents lesson steps one at a time with:
/// - A progress bar showing overall step completion
/// - Step content routed by step type (intro, listen, sing, exercise, quiz, read, practice)
/// - Navigation controls that respect step gating (locked/unlocked)
/// - A toolbar close button and step counter
///
/// ## Step Gating
/// Each step type has a gate condition. For example, a "listen" step is locked
/// until the audio finishes playing, and a "quiz" step is locked until all
/// questions are answered. The "Next" button is disabled while the gate is locked.
///
/// ## Lifecycle
/// On appear, creates the `LessonPlayerViewModel`, which restores the resume
/// position from `LessonProgress`. On disappear, persists elapsed session time.
struct LessonStepView: View {
    // MARK: - Properties

    /// The lesson being studied.
    let lesson: Lesson

    /// Progress manager for step and lesson completion persistence.
    let progressManager: LessonProgressManager

    /// Callback invoked when the lesson is completed.
    let onComplete: () -> Void

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.modelContext)
    private var modelContext
    @Environment(GamificationService.self)
    private var gamificationService: GamificationService?
    @Environment(AppThemeManager.self)
    var themeManager  // internal so the +StepContent extension (separate file) can read it

    /// The lesson player view model managing state and progression.
    @State
    private var viewModel: LessonPlayerViewModel?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    phaseContent(viewModel: viewModel)
                } else {
                    ProgressView("Loading lesson…")
                        .accessibilityLabel(Text("Loading lesson"))
                }
            }
            .navigationTitle(lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Close lesson"))
                    .accessibilityHint(Text("Double tap to exit the lesson"))
                }

                if let viewModel, case .active = viewModel.phase {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(
                            "\(viewModel.currentStepIndex + 1) of \(viewModel.totalSteps)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            Text(
                                "Step \(viewModel.currentStepIndex + 1) of \(viewModel.totalSteps)"
                            )
                        )
                    }
                }
            }
        }
        .onAppear {
            let vm = LessonPlayerViewModel(
                lesson: lesson,
                progressManager: progressManager,
                gamificationService: gamificationService
            )
            vm.onAppear()
            viewModel = vm
        }
        .onDisappear {
            viewModel?.onDisappear()
        }
    }

    // MARK: - Phase Content

    /// Routes to the appropriate content based on the player phase.
    ///
    /// - Parameter viewModel: The lesson player view model.
    /// - Returns: The view for the current phase.
    @ViewBuilder
    private func phaseContent(viewModel: LessonPlayerViewModel) -> some View {
        switch viewModel.phase {
        case .loading:
            ProgressView("Loading lesson…")
                .accessibilityLabel(Text("Loading lesson"))

        case .active:
            VStack(spacing: 0) {
                // Progress bar
                progressBar(viewModel: viewModel)

                // Step content
                ScrollView {
                    stepContent(viewModel: viewModel)
                        .padding()
                        .id(viewModel.currentStepIndex)
                }

                // Gate status indicator
                if case .locked(let reason) = viewModel.gateStatus {
                    gateIndicator(reason: reason)
                }

                Divider()

                // Navigation controls
                navigationControls(viewModel: viewModel)
                    .padding()
            }

        case .completed:
            completedContent
        }
    }

    // MARK: - Progress Bar

    /// Progress bar showing step completion fraction.
    ///
    /// - Parameter viewModel: The lesson player view model.
    /// - Returns: A thin horizontal bar indicating progress.
    private func progressBar(viewModel: LessonPlayerViewModel) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(themeManager.resolved.dividerColor)

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(
                        width: geometry.size.width * viewModel.progressFraction
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.3),
                        value: viewModel.progressFraction
                    )
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    // MARK: - Step Content Router

    /// Routes to the appropriate step type view based on the current step.
    ///
    /// Each step type renders a badge header, the main content, and
    /// step-type-specific interactive elements. Interactive steps (listen,
    /// sing, exercise, quiz) call back to the view model when completed.
    ///
    /// - Parameter viewModel: The lesson player view model.
    /// - Returns: The content view for the current step type.
    @ViewBuilder
    private func stepContent(viewModel: LessonPlayerViewModel) -> some View {
        if let step = viewModel.currentStep {
            VStack(alignment: .leading, spacing: 16) {
                // Step type badge
                stepTypeBadge(step: step)

                // Route to step-type-specific content
                stepTypeContent(step: step, viewModel: viewModel)

                // Duration indicator (if available)
                if let seconds = step.durationSeconds {
                    Label(
                        durationLabel(seconds),
                        systemImage: "timer"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Badge showing the step type with icon and label.
    ///
    /// - Parameter step: The current lesson step.
    /// - Returns: A capsule-styled badge.
    private func stepTypeBadge(step: LessonStep) -> some View {
        HStack {
            Image(systemName: stepTypeIcon(step.stepType))
                .foregroundStyle(StepTypeColorSystem.color(forStepType: step.stepType))
            Text(stepTypeLabel(step.stepType))
                .fontWeight(.semibold)
                .foregroundStyle(StepTypeColorSystem.color(forStepType: step.stepType))
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(StepTypeColorSystem.color(forStepType: step.stepType).opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step type: \(stepTypeLabel(step.stepType))"))
    }

    /// Routes to the correct content view based on step type.
    ///
    /// - Parameters:
    ///   - step: The current lesson step.
    ///   - viewModel: The lesson player view model for callbacks.
    /// - Returns: The step-type-specific content view.
    @ViewBuilder
    private func stepTypeContent(step: LessonStep, viewModel: LessonPlayerViewModel) -> some View {
        let song = resolveSong(for: step.songId)

        switch step.stepType {
        case "intro", "read":
            introReadContent(step: step)

        case "listen":
            listenContent(step: step, song: song, viewModel: viewModel)

        case "sing":
            singContent(step: step, song: song, viewModel: viewModel)

        case "exercise", "practice":
            exerciseContent(step: step, song: song, viewModel: viewModel)

        case "quiz":
            quizContent(step: step, viewModel: viewModel)

        default:
            Text(verbatim: step.content)
                .font(.body)
                .lineSpacing(6)
        }
    }

    /// Resolves a `LessonStep.songId` to a `Song` from the model context.
    ///
    /// Returns `nil` if the step has no song ID or if no matching song exists.
    ///
    /// - Parameter songId: The optional song UUID from a `LessonStep`.
    /// - Returns: The matching `Song`, or `nil`.
    private func resolveSong(for songId: UUID?) -> Song? {
        guard let songId else { return nil }
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == songId }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Step Type Views & Helpers

private extension LessonStepView {

    // MARK: Gate Indicator

    /// Displays the current gate lock reason.
    ///
    /// - Parameter reason: The user-facing reason the step is locked.
    /// - Returns: A subtle banner explaining why the Next button is disabled.
    func gateIndicator(reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(themeManager.resolved.warningColor)
                .accessibilityHidden(true)

            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.resolved.cardBackgroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step locked: \(reason)"))
    }

    // MARK: Navigation Controls

    /// Executes an action with optional animation respecting reduce motion.
    func animatedAction(_ action: @escaping () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        }
    }

    /// Navigation buttons (Previous / Next / Complete).
    ///
    /// The "Next" button is disabled when the step gate is locked.
    /// On the last step, shows "Complete Lesson" instead of "Next".
    ///
    /// - Parameter viewModel: The lesson player view model.
    /// - Returns: A horizontal stack of navigation buttons.
    func navigationControls(viewModel: LessonPlayerViewModel) -> some View {
        HStack {
            Button { animatedAction { viewModel.goToPreviousStep() } } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(.body).fontWeight(.medium)
            }
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel(Text("Previous step"))
            .accessibilityHint(Text("Double tap to go to the previous step"))

            Spacer()

            if viewModel.isLastStep {
                completeLessonButton(viewModel: viewModel)
            } else {
                nextStepButton(viewModel: viewModel)
            }
        }
    }

    /// "Complete Lesson" button shown on the last step.
    func completeLessonButton(viewModel: LessonPlayerViewModel) -> some View {
        Button { animatedAction { viewModel.goToNextStep() } } label: {
            Text("Complete Lesson")
                .font(.body).fontWeight(.semibold)
                .foregroundStyle(themeManager.resolved.badgeTextColor)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(viewModel.canGoNext ? .green : .gray))
        }
        .disabled(!viewModel.canGoNext)
        .accessibilityLabel(Text("Complete lesson"))
        .accessibilityHint(Text("Double tap to mark this lesson as completed and close"))
    }

    /// "Next" button shown for non-final steps.
    func nextStepButton(viewModel: LessonPlayerViewModel) -> some View {
        Button { animatedAction { viewModel.goToNextStep() } } label: {
            Label("Next", systemImage: "chevron.right")
                .font(.body).fontWeight(.medium)
                .labelStyle(.titleAndIcon)
        }
        .disabled(!viewModel.canGoNext)
        .accessibilityLabel(Text("Next step"))
        .accessibilityHint(Text("Double tap to go to the next step"))
    }

    // MARK: Completed Content

    /// Content shown when the lesson is completed.
    ///
    /// Fires the `onComplete` callback and dismisses the view on appear.
    var completedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(themeManager.resolved.successColor)
                .accessibilityHidden(true)

            Text("Lesson Complete!")
                .font(.title2)
                .fontWeight(.bold)

            if let viewModel, let score = viewModel.quizScore {
                Text("Quiz Score: \(Int(score * 100))%")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text("Great work! You've completed this lesson.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onComplete()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(themeManager.resolved.badgeTextColor)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentColor)
                    )
            }
            .padding(.horizontal, 40)
            .accessibilityLabel(Text("Done"))
            .accessibilityHint(Text("Double tap to close the lesson"))
        }
        .padding()
        .onAppear {
            // Trigger completion callback when the completed phase appears
            onComplete()
        }
    }
}
