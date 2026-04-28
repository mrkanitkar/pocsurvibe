import SwiftUI

/// Lists open-source attribution required by the licenses of bundled
/// third-party assets and libraries.
///
/// Reachable from `ProfileTab` → "About" section → "Acknowledgements".
/// Surfaced on iPad (the iOS Settings scene is inert on iPad/iOS); the
/// route value is the string `"acknowledgements"`, dispatched by
/// `ProfileTab`'s `.navigationDestination(for: String.self)`.
struct AcknowledgementsView: View {

    var body: some View {
        Form {
            Section {
                attributionEntry(
                    title: "MuseScore_General Soundfont",
                    license: "MIT",
                    lines: [
                        "FluidR3 by Frank Wen © 2000-2002",
                        "FluidR3Mono mono conversion by Michael Cowgill © 2014-2017",
                        "Adaptation for MS_General.sf2 by S. Christian Collins © 2018",
                        "Temple Blocks instrument by Ethan Winer © 2002",
                        "Drumline Percussion by Michael Schorsch © 2016"
                    ]
                )
            } header: {
                Text("Audio")
            } footer: {
                Text("Bundled SoundFont used for in-app instrument playback.")
            }

            Section("Music Engraving") {
                attributionEntry(
                    title: "Verovio",
                    license: "LGPL v3",
                    lines: [
                        "© RISM Digital Center",
                        "https://www.verovio.org"
                    ]
                )
            }

            Section("Audio Frameworks") {
                attributionEntry(
                    title: "AudioKit",
                    license: "MIT",
                    lines: [
                        "https://github.com/AudioKit/AudioKit"
                    ]
                )
            }
        }
        .navigationTitle("Acknowledgements")
    }

    @ViewBuilder
    private func attributionEntry(title: String, license: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), licensed under \(license)")
        .accessibilityHint("\(lines.count) attribution \(lines.count == 1 ? "line" : "lines")")
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
