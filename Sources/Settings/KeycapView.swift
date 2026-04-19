import SwiftUI

/// Renders a `ShortcutSpec` as a row of small keycap pills, one per
/// modifier glyph plus the key glyph. Matches the visual vocabulary
/// most macOS preference panes use for shortcuts.
struct KeycapView: View {

    let spec: ShortcutSpec
    var isDimmed: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(orderedModifiers, id: \.self) { key in
                cap(key.symbol)
            }
            cap(keyGlyph)
        }
        .opacity(isDimmed ? 0.55 : 1)
    }

    // MARK: - Content

    /// Canonical modifier order: ⌃ ⌥ ⇧ ⌘ (mirrors Apple's menu layout).
    private var orderedModifiers: [ModifierKey] {
        let present = spec.modifiers.asSet
        return [.control, .option, .shift, .command].filter { present.contains($0) }
    }

    private var keyGlyph: String {
        ShortcutKeyTable.glyph(for: spec.keyCode) ?? "?"
    }

    // MARK: - Primitive

    private func cap(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
            )
    }
}
