import SwiftUI

/// Hero-theme notation renderer: RH melody row on top, LH drone/chord row below.
///
/// Used exclusively by Sargam Glass · Bars (#8 default). Mirrors Hindustani
/// practice where a student learns melody over a sustained tanpura drone.
///
/// Top row: the 7 swars सा-नि scroll horizontally; the current swar is
/// scaled up and drawn with `rhColor`.
///
/// Bottom row: the current drone swar is drawn in `lhColor`; a chord cluster
/// (if multiple LH notes overlap at the same beat) is drawn inside a
/// rounded card with `chordColor` border.
///
/// ## Latency contract
/// Colors arrive as `let` parameters. No `@Environment(AppThemeManager.self)`.
struct SargamDualRowView: View {
    let noteEvents: [NoteEvent]
    let currentTime: TimeInterval
    let rhColor: Color
    let lhColor: Color
    let chordColor: Color
    let cardBackgroundColor: Color

    /// The 7 classical Hindustani swars, in order.
    private static let swars: [String] = ["सा", "रे", "ग", "म", "प", "ध", "नि"]
    private static let swarRomans: [String] = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]

    var body: some View {
        VStack(spacing: 8) {
            rhRow
            lhRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sargam dual-row notation: right-hand melody above, left-hand drone below")
    }

    // MARK: - Right-hand melody row

    private var rhRow: some View {
        HStack(alignment: .center, spacing: 8) {
            rowLabel(text: "RH · Melody", color: rhColor)
            HStack(alignment: .center, spacing: 6) {
                ForEach(Array(Self.swars.enumerated()), id: \.offset) { index, swar in
                    swarItem(
                        devanagari: swar,
                        roman: Self.swarRomans[index],
                        isActive: isActiveSwar(index: index, hand: .right),
                        accentColor: rhColor
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Left-hand drone/chord row

    private var lhRow: some View {
        HStack(alignment: .center, spacing: 8) {
            rowLabel(text: "LH · Drone", color: lhColor)
            Spacer()
            if chordActive {
                chordClusterCard
            } else {
                droneItem
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Subviews

    private func rowLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }

    private func swarItem(devanagari: String, roman: String, isActive: Bool, accentColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(devanagari)
                .font(.system(size: isActive ? 28 : 22, weight: .bold))
                .foregroundStyle(isActive ? accentColor : .secondary.opacity(0.5))
                .scaleEffect(isActive ? 1.1 : 1.0)
            Text(roman)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(isActive ? accentColor : .secondary.opacity(0.5))
                .textCase(.uppercase)
        }
    }

    private var droneItem: some View {
        swarItem(devanagari: "सा", roman: "Sa", isActive: true, accentColor: lhColor)
    }

    private var chordClusterCard: some View {
        VStack(spacing: 2) {
            Text("सा")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(chordColor)
            Text("ग")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(chordColor)
            Text("प")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(chordColor)
            Text("CHORD 1·3·5")
                .font(.system(size: 6, weight: .heavy))
                .foregroundStyle(chordColor)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chordColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(chordColor, lineWidth: 1)
        )
    }

    // MARK: - Derived state

    /// True if at the current time there are ≥2 LH notes starting at the same beat.
    private var chordActive: Bool {
        let concurrent = noteEvents.filter { event in
            event.hand == .left
                && currentTime >= event.timestamp
                && currentTime <= event.timestamp + event.duration
        }
        return concurrent.count >= 2
    }

    /// Return true if the swar at `index` in the carousel is the current one being played by `hand`.
    private func isActiveSwar(index: Int, hand: Hand) -> Bool {
        let active = noteEvents.filter { event in
            event.hand == hand
                && currentTime >= event.timestamp
                && currentTime <= event.timestamp + event.duration
        }
        // Map MIDI note modulo 12 → swar index (rough mapping Sa=C=0, Re=D=2, etc.)
        // Simplified: use (midiNote % 12) to pick one of 12 semitones, 7 of which are swars.
        // For robustness with komal/tivra, swar index defaults to nearest 7-swar.
        for event in active {
            let semitone = Int(event.midiNote) % 12
            let swarIndex: Int? = {
                switch semitone {
                case 0: return 0  // Sa
                case 1, 2: return 1  // Komal Re / Re
                case 3, 4: return 2  // Komal Ga / Ga
                case 5, 6: return 3  // Ma / Tivra Ma
                case 7: return 4  // Pa
                case 8, 9: return 5  // Komal Dha / Dha
                case 10, 11: return 6  // Komal Ni / Ni
                default: return nil
                }
            }()
            if swarIndex == index { return true }
        }
        return false
    }
}

#Preview("Empty") {
    SargamDualRowView(
        noteEvents: [],
        currentTime: 0,
        rhColor: Color(red: 0.00, green: 0.48, blue: 1.00),
        lhColor: Color(red: 1.00, green: 0.23, blue: 0.19),
        chordColor: Color(red: 0.61, green: 0.15, blue: 0.69),
        cardBackgroundColor: Color.white.opacity(0.55)
    )
    .padding()
    .background(
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.96, blue: 0.90),
                Color(red: 1.0, green: 0.85, blue: 0.66)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
