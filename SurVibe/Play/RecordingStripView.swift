// SurVibe/Play/RecordingStripView.swift
import SwiftUI

/// Bottom strip showing the user's recorded notes (last up to 16) plus a
/// Clear button and counter. When the strip is full, the counter color
/// shifts to amber to signal the lock.
struct RecordingStripView: View {
    let recordedNotes: [RecordedNote]
    let saPitch: UInt8
    let notationMode: PlayTabNotationMode
    let onClear: () -> Void

    private let cap = 16

    var body: some View {
        HStack(spacing: 16) {
            stripContent
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text("\(recordedNotes.count) / \(cap)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(recordedNotes.count >= cap ? Color.orange : Color.secondary)

                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(recordedNotes.isEmpty)
                .accessibilityLabel("Clear recording strip")
                .accessibilityHint("Removes all recorded notes")
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var stripContent: some View {
        if recordedNotes.isEmpty {
            Text("Play a note to start recording")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recordedNotes) { note in
                        noteCell(for: note)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func noteCell(for note: RecordedNote) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "music.note")
                .font(.title2)
            Text(SargamLabeler.label(midi: note.midi, saPitch: saPitch).display)
                .font(.caption2)
                .monospaced()
        }
        .frame(width: 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            SargamLabeler.label(midi: note.midi, saPitch: saPitch).voiceOverDescription
        )
    }
}

#Preview("Empty") {
    RecordingStripView(
        recordedNotes: [],
        saPitch: 60,
        notationMode: .both,
        onClear: {}
    )
    .padding()
}

#Preview("3 notes") {
    RecordingStripView(
        recordedNotes: [
            RecordedNote(midi: 60, timestamp: .now),
            RecordedNote(midi: 64, timestamp: .now),
            RecordedNote(midi: 67, timestamp: .now),
        ],
        saPitch: 60,
        notationMode: .both,
        onClear: {}
    )
    .padding()
}

#Preview("Full (16/16)") {
    RecordingStripView(
        recordedNotes: (60..<76).map { RecordedNote(midi: UInt8($0), timestamp: .now) },
        saPitch: 60,
        notationMode: .both,
        onClear: {}
    )
    .padding()
}
