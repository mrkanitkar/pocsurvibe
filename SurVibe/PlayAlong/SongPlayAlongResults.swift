// SurVibe/PlayAlong/Lean/SongPlayAlongResults.swift
import SwiftUI

/// Lean results sheet shown when a song completes.
///
/// Displays accuracy + hit count + two buttons (Replay, Done). Replaces
/// the 339-line `PlayAlongResultsOverlay` + `PlayAlongResultsOverlay+Split`.
@MainActor
struct SongPlayAlongResults: View {
    let songTitle: String
    let accuracyPercent: Int
    let notesHit: Int
    let totalNotes: Int
    let onReplay: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(songTitle)
                    .font(.title2.bold())
                Text("Session complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("\(accuracyPercent)%")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(.tint)
                Text("\(notesHit) of \(totalNotes) notes")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button(action: onReplay) {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Replay song")

                Button(action: onDone) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Close results")
            }
            .padding(.top, 12)
        }
        .padding(28)
        .frame(maxWidth: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}
