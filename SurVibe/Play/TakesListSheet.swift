// SurVibe/Play/TakesListSheet.swift
import SVCore
import SwiftData
import SwiftUI

/// Modal sheet listing every saved ``RecordedTake``, newest first.
///
/// Supports two CRUD operations on top of the trunk's create-only flow
/// (T16a): swipe-to-delete with a 3 second Undo banner, and rename via a
/// long-press context menu that drops into an alert with a text field.
/// Tap-to-open / export are deferred to T16c — this sheet only renders the
/// list and offers delete + rename.
///
/// Delete is *deferred*, not optimistic: the row stays visible (struck
/// through, dimmed) and a banner with an **Undo** button overlays the list.
/// If the user does nothing for three seconds the take is hard-deleted from
/// the model context. Cancel before the timer fires and the row is restored.
struct TakesListSheet: View {
    @Query(sort: \RecordedTake.createdAt, order: .reverse) private var takes: [RecordedTake]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var renaming: RecordedTake?
    @State private var renameTitle: String = ""

    @State private var pendingDelete: RecordedTake?
    @State private var undoTimer: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Takes")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert(
                    "Rename take",
                    isPresented: Binding(
                        get: { renaming != nil },
                        set: { if !$0 { renaming = nil } }
                    )
                ) {
                    TextField("Title", text: $renameTitle)
                    Button("Save") { commitRename() }
                    Button("Cancel", role: .cancel) { renaming = nil }
                } message: {
                    Text("Give this take a new title.")
                }
                .overlay(alignment: .bottom) { undoBanner }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { finalizePendingDelete() }
    }

    // MARK: - List vs. empty state

    @ViewBuilder
    private var content: some View {
        if takes.isEmpty {
            ContentUnavailableView(
                "No saved takes yet",
                systemImage: "music.note.list",
                description: Text("Save a recording to see your takes here.")
            )
        } else {
            List {
                ForEach(takes) { take in
                    row(for: take)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                scheduleDelete(take)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityLabel("Delete \(take.title)")
                        }
                        .contextMenu {
                            Button {
                                renaming = take
                                renameTitle = take.title
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                scheduleDelete(take)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for take: RecordedTake) -> some View {
        let isPendingDelete = pendingDelete?.id == take.id
        VStack(alignment: .leading, spacing: 4) {
            Text(take.title)
                .font(.headline)
                .strikethrough(isPendingDelete)
            Text(metadataLine(for: take))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(isPendingDelete ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: take))
        .accessibilityHint("Swipe left to delete. Long-press to rename.")
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let pending = pendingDelete {
            HStack(spacing: 12) {
                Text("Deleted \(pending.title)")
                    .font(.subheadline)
                Spacer()
                Button("Undo") { undoDelete() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityHint("Restores the take. The deletion is finalized in three seconds otherwise.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Delete (with undo)

    /// Marks `take` as pending deletion and starts a 3 second undo window.
    /// If the user taps **Undo** the timer is cancelled. Otherwise the take
    /// is deleted from the model context and the change is saved.
    private func scheduleDelete(_ take: RecordedTake) {
        // If another delete is mid-flight, finalize it immediately so we
        // never have two pending takes vying for the same banner.
        finalizePendingDelete()

        pendingDelete = take
        undoTimer = Task { [id = take.id] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { commitDelete(takeID: id) }
        }
    }

    /// Cancel the pending delete and clear the banner.
    private func undoDelete() {
        undoTimer?.cancel()
        undoTimer = nil
        pendingDelete = nil
    }

    /// Finalize whatever delete is currently pending — used on disappear so
    /// dismissing the sheet doesn't strand the in-memory pending take.
    private func finalizePendingDelete() {
        guard let take = pendingDelete else { return }
        undoTimer?.cancel()
        undoTimer = nil
        commitDelete(takeID: take.id)
    }

    private func commitDelete(takeID: UUID) {
        guard let take = pendingDelete, take.id == takeID else { return }
        modelContext.delete(take)
        do {
            try modelContext.save()
        } catch {
            // Save failure is recoverable: the next autosave will retry,
            // and the take is already gone from the context. Log only.
            // (No user-visible error path on this sheet in v2.)
        }
        pendingDelete = nil
        undoTimer = nil
    }

    // MARK: - Rename

    private func commitRename() {
        guard let target = renaming else { return }
        let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            target.title = trimmed
            try? modelContext.save()
        }
        renaming = nil
    }

    // MARK: - Row formatting

    private func metadataLine(for take: RecordedTake) -> String {
        let instrument = GMInstrumentCatalog.name(for: take.instrumentProgram)
        let duration = formatClock(take.durationSec)
        let sa = midiNoteName(take.saPitchMidi)
        return "\(instrument) · \(duration) · \(take.noteCount) notes · Sa = \(sa)"
    }

    private func accessibilityLabel(for take: RecordedTake) -> String {
        "\(take.title), \(GMInstrumentCatalog.name(for: take.instrumentProgram)), "
            + "\(take.noteCount) notes, "
            + "duration \(formatClock(take.durationSec)), "
            + "Sa \(midiNoteName(take.saPitchMidi))"
    }

    /// Formats a duration in seconds as `m:ss`. Negative durations are
    /// clamped to zero so a corrupt take never renders as "-1:00".
    private func formatClock(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalSeconds = Int(clamped.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Returns the conventional Western letter name + octave for a MIDI
    /// note number using the MIDI 1.0 convention where note 60 = C4.
    private func midiNoteName(_ midi: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(midi) / 12 - 1
        let pitchClass = Int(midi) % 12
        return "\(names[pitchClass])\(octave)"
    }
}

#Preview("Empty") {
    TakesListSheet()
        .modelContainer(for: RecordedTake.self, inMemory: true)
}

#Preview("Populated") {
    PopulatedTakesPreview()
}

private struct PopulatedTakesPreview: View {
    private let container: ModelContainer? = {
        do {
            let container = try ModelContainer(
                for: RecordedTake.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = container.mainContext
            context.insert(RecordedTake(
                title: "Take 1 · 29 Apr 19:42",
                instrumentProgram: 0,
                saPitchMidi: 60,
                notes: [],
                sustain: []
            ))
            context.insert(RecordedTake(
                title: "Yaman alaap",
                instrumentProgram: 40,
                saPitchMidi: 62,
                notes: [],
                sustain: []
            ))
            return container
        } catch {
            return nil
        }
    }()

    var body: some View {
        if let container {
            TakesListSheet().modelContainer(container)
        } else {
            ContentUnavailableView("Preview unavailable", systemImage: "xmark.circle")
        }
    }
}
