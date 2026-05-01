import SVCore
import SwiftUI

/// A compact horizontal preview of notation for a song card.
///
/// Post-T5', song notation is stored as MIDI binary data rather than
/// decoded JSON note arrays. Full notation rendering requires the async
/// `VerovioBridge` pipeline, which is too heavyweight for a thumbnail.
/// This view renders a stylised empty staff with the song title as a
/// "notation coming soon" placeholder until a lightweight thumbnail
/// pipeline is implemented.
struct MiniNotationPreview: View {
    // MARK: - Properties

    /// The song whose notation to preview.
    let song: Song

    // MARK: - Body

    var body: some View {
        ZStack {
            staffLines
            titleLabel
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notation preview for \(song.title) — not yet available")
    }

    // MARK: - Private Views

    /// Five horizontal staff lines drawn as a Canvas for efficiency.
    private var staffLines: some View {
        Canvas { ctx, size in
            let lineCount = 5
            let topPad: CGFloat = 4
            let bottomPad: CGFloat = 4
            let usable = size.height - topPad - bottomPad
            let spacing = usable / CGFloat(lineCount - 1)

            for i in 0..<lineCount {
                let y = topPad + CGFloat(i) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            }
        }
    }

    /// Song title centred over the staff as a subtle label.
    private var titleLabel: some View {
        Text(verbatim: song.title)
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.6))
            .lineLimit(1)
            .padding(.horizontal, 6)
    }
}
