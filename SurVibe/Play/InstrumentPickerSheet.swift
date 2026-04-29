// SurVibe/Play/InstrumentPickerSheet.swift
import SwiftUI

/// Modal sheet for picking a General MIDI program.
///
/// Categories collapse into `Section`s; a `.searchable` field filters across
/// instrument names. Selection dismisses the sheet and invokes `onSelect`.
struct InstrumentPickerSheet: View {
    let currentProgram: UInt8
    let onSelect: (UInt8) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var searchText: String = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(
                            GMInstrumentCatalog.entries(in: category)
                                .filter { matches(searchText: searchText, name: $0.name) }
                        ) { instrument in
                            row(for: instrument)
                        }
                    }
                }
            }
            .navigationTitle("Instruments")
            .searchable(text: $searchText, prompt: "Search instruments")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for instrument: GMInstrument) -> some View {
        Button {
            onSelect(instrument.program)
            dismiss()
        } label: {
            HStack {
                Text(instrument.name)
                    .foregroundStyle(.primary)
                Spacer()
                if instrument.program == currentProgram {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityLabel(instrument.name)
        .accessibilityHint(
            instrument.program == currentProgram ? "Currently selected" : "Select \(instrument.name)"
        )
    }

    private var filteredCategories: [GMInstrumentCategory] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return GMInstrumentCategory.allCases }
        return GMInstrumentCategory.allCases.filter { category in
            GMInstrumentCatalog.entries(in: category).contains { matches(searchText: trimmed, name: $0.name) }
        }
    }

    private func matches(searchText: String, name: String) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.range(of: trimmed, options: .caseInsensitive) != nil
    }
}

#Preview("Default") {
    InstrumentPickerSheet(currentProgram: 0) { _ in }
}

#Preview("Selected guitar") {
    InstrumentPickerSheet(currentProgram: 24) { _ in }
}
