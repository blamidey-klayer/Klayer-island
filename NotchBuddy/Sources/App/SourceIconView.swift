import SwiftUI

// MARK: - Source icons (Task 27)

/// The icon that says where a row or a note comes from (`SourceIcon`): `</>` for a Claude Code
/// session, the Claude mark for Chat and Cowork. The mark is a neutral SF Symbol from one constant
/// (`ClaudeMark`), the only place to change once a founder approves the official asset; nothing here
/// draws or embeds a Claude or Anthropic logo. Drawn in the colour of the state, `size` points square,
/// the size of the mini Klay it replaces on the rows.
struct SourceIconView: View {
    let icon: SourceIcon
    let color: Color
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: icon.symbolName)
            .font(.system(size: size * 0.6, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            // « Session Code », « App Claude »: French keys of the catalogue.
            .accessibilityLabel(Text(LocalizedStringKey(icon.accessibilityLabel)))
    }
}

extension StateColor {
    /// The colour of a session's phase (the phases have the raw values of the states).
    static func color(of phase: SessionPhase) -> Color {
        Color(cgColor: of(BotState(rawValue: phase.rawValue) ?? .idle))
    }
}

extension View {
    /// The home's list as a wheel (`ListWheel`, Task 27): a row near the centre of the list is whole,
    /// towards the top and the bottom it shrinks, fades and moves slightly right. Computed by the
    /// scroll view while the list moves, nothing at rest.
    func listWheel() -> some View {
        scrollTransition(.interactive.threshold(.centered), axis: .vertical) { content, phase in
            let look = ListWheel.look(phase: phase.value)
            return content
                .scaleEffect(CGFloat(look.scale), anchor: .leading)
                .opacity(look.opacity)
                .offset(x: CGFloat(look.xOffset), y: 0)
        }
    }
}
