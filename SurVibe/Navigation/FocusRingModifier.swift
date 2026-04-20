import SwiftUI

/// Draws a 3pt stroke in the supplied accent colour when this item's `id`
/// matches the currently-focused `@FocusState` binding value.
///
/// Used by library cards, HomeTab DoorCards, and ProfileTab rows so the
/// system focus indicator is visually consistent across surfaces.
///
/// - Parameters:
///   - itemID: The identity of the view this modifier is attached to.
///   - focusedID: The currently-focused identity (or `nil`).
///   - accent: The stroke colour (typically `themeManager.resolved.accentColor`).
///   - cornerRadius: Corner radius of the focus ring. Defaults to 12.
struct FocusRingModifier<ID: Hashable>: ViewModifier {
    let itemID: ID
    let focusedID: ID?
    let accent: Color
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content.overlay {
            if focusedID == itemID {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(accent, lineWidth: 3)
            }
        }
    }
}

extension View {
    /// Attaches a focus-ring overlay that appears when `itemID == focusedID`.
    ///
    /// Sugar for `.modifier(FocusRingModifier(itemID:focusedID:accent:))`.
    func focusRing<ID: Hashable>(
        itemID: ID,
        focusedID: ID?,
        accent: Color,
        cornerRadius: CGFloat = 12
    ) -> some View {
        modifier(FocusRingModifier(itemID: itemID, focusedID: focusedID, accent: accent, cornerRadius: cornerRadius))
    }
}
