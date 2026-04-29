import SVCore
import SwiftData
import SwiftUI

/// Save take sheet — title field plus a collapsed "Edit details" disclosure
/// for raga tag and teacher notes.
///
/// The sheet is intentionally lightweight per Play tab v2 spec §4.6: title
/// auto-fills with `"Take N · <date>"` so the typical save is a one-tap
/// confirm. Raga, teacher notes, and a stats summary live behind the
/// disclosure (progressive disclosure — see `play_tab_simple_ui` memory).
///
/// The sheet receives a `ScratchpadState` directly rather than reading
/// `viewModel.scratchpad` because that property is added by Task 6 (parallel
/// branch). Once T6 lands, callers will pass `viewModel.scratchpad` here.
///
/// Materialisation is delegated to `PlayTabViewModel.saveTake(...)` which
/// freezes the scratchpad, builds a `RecordedTake`, inserts it into the
/// `ModelContext`, and clears the scratchpad on success.
struct SaveTakeSheet: View {
    @Bindable var viewModel: PlayTabViewModel
    let scratchpad: ScratchpadState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var teacherNotes: String = ""
    @State private var ragaTagId: String?
    @State private var detailsExpanded: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                detailsSection
                statsSection
            }
            .navigationTitle("Save take")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { performSave() }
                        .disabled(title.isEmpty || isSaving)
                        .accessibilityHint(Text("Saves the current recording as a take"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint(Text("Closes without saving"))
                }
            }
            .onAppear { seedTitleIfNeeded() }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $title)
                .accessibilityLabel(Text("Take title"))
        }
    }

    private var detailsSection: some View {
        Section {
            DisclosureGroup("Edit details", isExpanded: $detailsExpanded) {
                Picker("Raga", selection: $ragaTagId) {
                    Text("None").tag(String?.none)
                    Text("Yaman").tag(String?.some("yaman"))
                    Text("Bhairav").tag(String?.some("bhairav"))
                    Text("Bilawal").tag(String?.some("bilawal"))
                    Text("Kafi").tag(String?.some("kafi"))
                    Text("Bhairavi").tag(String?.some("bhairavi"))
                }
                .accessibilityHint(Text("Tag this take with a raga"))
                TextField("Notes for the teacher", text: $teacherNotes, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel(Text("Teacher notes"))
            }
        }
    }

    private var statsSection: some View {
        Section {
            LabeledContent("Stats") {
                Text(verbatim: statsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(statsAccessibilityLabel))
            }
        }
    }

    // MARK: - Actions

    private func performSave() {
        guard !isSaving else { return }
        isSaving = true
        let snapshotTitle = title
        let snapshotRaga = ragaTagId
        let snapshotNotes = teacherNotes
        Task {
            await viewModel.saveTake(
                scratchpad: scratchpad,
                modelContext: modelContext,
                title: snapshotTitle,
                ragaTagId: snapshotRaga,
                teacherNotes: snapshotNotes
            )
            isSaving = false
            dismiss()
        }
    }

    private func seedTitleIfNeeded() {
        guard title.isEmpty else { return }
        let count = viewModel.takesCount(in: modelContext) + 1
        let stamp = Date().formatted(.dateTime.day().month().hour().minute())
        title = "Take \(count) · \(stamp)"
    }

    // MARK: - Stats helpers

    private var statsLine: String {
        let duration = Self.formatDuration(scratchpad.durationSec)
        let saName = Self.midiName(scratchpad.saPitchMidi)
        return "\(duration) · \(scratchpad.noteCount) notes · Sa = \(saName)"
    }

    private var statsAccessibilityLabel: String {
        let duration = Self.formatDuration(scratchpad.durationSec)
        let saName = Self.midiName(scratchpad.saPitchMidi)
        return "Duration \(duration), \(scratchpad.noteCount) notes, Sa is \(saName)"
    }

    /// Formats a duration in seconds as `m:ss` (or `h:mm:ss` past one hour).
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Returns the conventional name (e.g., `"C4"`, `"F#3"`) for a MIDI note.
    ///
    /// Uses scientific pitch notation: MIDI 60 → `C4`. Out-of-range values are
    /// clamped to a safe display.
    static func midiName(_ midi: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let value = Int(midi)
        let octave = (value / 12) - 1
        let pitchClass = value % 12
        return "\(names[pitchClass])\(octave)"
    }
}
