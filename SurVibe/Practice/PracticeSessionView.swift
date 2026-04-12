import SVAudio
import SVLearning
import SwiftData
import SwiftUI

/// Main container view for a practice session.
///
/// Switches between sub-views based on the current practice phase:
/// loading, listen-first, practice-along, completed, or error.
/// Presented as a full-screen cover from `SongDetailView`.
struct PracticeSessionView: View {
    @State private var viewModel: PracticeSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let song: Song

    init(song: Song, modelContext: ModelContext, gamificationService: GamificationService? = nil) {
        self.song = song
        _viewModel = State(
            initialValue: PracticeSessionViewModel(
                modelContext: modelContext,
                gamificationService: gamificationService
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch viewModel.phase {
                case .loading:
                    ProgressView("Preparing practice session...")
                        .accessibilityLabel("Loading practice session")

                case .listenFirst:
                    ListenFirstView(viewModel: viewModel)

                case .practiceAlong:
                    PracticeAlongView(viewModel: viewModel)

                case .completed:
                    completedContent

                case .error(let message):
                    errorContent(message: message)
                }
            }
            .navigationTitle(viewModel.song?.title ?? "Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.cleanup()
                        dismiss()
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("End practice and return to the song")
                }
            }
        }
        .task {
            await viewModel.loadSong(song)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Completed Phase

    /// Content shown when the practice session is complete.
    private var completedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Practice Complete!")
                .font(.title)

            Text("Accuracy: \(Int(viewModel.sessionAccuracy * 100))%")
                .font(.title2)

            Text("Stars: \(viewModel.starRating) | XP: \(viewModel.xpEarned)")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("Practice Again") {
                    viewModel.restartPractice()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Practice again")
                .accessibilityHint(
                    "Restart the practice session from the beginning"
                )

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Done")
                .accessibilityHint("Return to the song detail screen")
            }
        }
        .padding()
    }

    // MARK: - Error Phase

    /// Content shown when an error occurs during the session.
    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Something went wrong")
                .font(.title2)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Go Back") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Go back")
            .accessibilityHint("Return to the previous screen")
        }
        .padding()
    }
}
