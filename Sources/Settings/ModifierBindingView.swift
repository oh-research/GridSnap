import SwiftUI

/// Settings sub-view for rebinding the Grip / Flip / Stretch roles to
/// physical modifier keys. Renders a 3×5 toggle grid, a live validation
/// message, and a reset button. Invalid selections are kept in-memory
/// (the user can recover) but never persisted — so coordinators on the
/// event-tap thread always read a valid binding.
struct ModifierBindingView: View {

    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var draft: ModifierBindings = .load()

    // `.function` is intentionally omitted: macOS auto-sets the Fn flag
    // on arrow keypresses, so a role bound to fn would match too permissively.
    // The strip-on-load migration in `ModifierBindings.load()` ensures any
    // previously stored fn bit is scrubbed regardless of UI exposure.
    private static let keys: [ModifierKey] = [.shift, .control, .option, .command]
    private static let roles: [ModifierRole] = [.grip, .flip, .stretch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            ForEach(Self.roles, id: \.self) { role in
                roleRow(role)
            }
            Divider()
            HStack {
                validationLabel
                Spacer()
                Button("Reset to defaults") { resetToDefaults() }
                    .font(.caption)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        // Suppress the auto-focus ring on the first toggle when the
        // Settings window opens — the Settings surface has no useful
        // keyboard navigation target, so the ring is pure noise.
        .focusEffectDisabled()
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 60)
            ForEach(Self.keys, id: \.self) { key in
                Text(key.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 32)
            }
        }
    }

    private func roleRow(_ role: ModifierRole) -> some View {
        HStack(spacing: 0) {
            Text(role.label)
                .font(.subheadline)
                .frame(width: 60, alignment: .leading)
            ForEach(Self.keys, id: \.self) { key in
                Toggle("", isOn: binding(for: role, key: key))
                    .labelsHidden()
                    .focusable(false)
                    .frame(width: 32)
            }
        }
    }

    private var validationLabel: some View {
        Group {
            if let message = firstIssueMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Valid", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
    }

    // MARK: - State bridging

    private func binding(for role: ModifierRole, key: ModifierKey) -> Binding<Bool> {
        Binding(
            get: { draft.keys(for: role).contains(PressedModifiers([key])) },
            set: { isOn in apply(role: role, key: key, include: isOn) }
        )
    }

    private func apply(role: ModifierRole, key: ModifierKey, include: Bool) {
        var updated = draft.keys(for: role)
        let mask = PressedModifiers([key])
        if include {
            updated.insert(mask)
        } else {
            updated.subtract(mask)
        }
        draft = ModifierBindings(
            grip:    role == .grip    ? updated : draft.grip,
            flip:    role == .flip    ? updated : draft.flip,
            stretch: role == .stretch ? updated : draft.stretch
        )
        if draft.isValid {
            prefs.updateBindings(draft)
        }
    }

    private func resetToDefaults() {
        draft = .default
        prefs.updateBindings(draft)
    }

    // MARK: - Validation message

    private var firstIssueMessage: String? {
        guard let issue = draft.validate().first else { return nil }
        switch issue {
        case .empty(let role):
            return "\(role.label) needs at least one modifier"
        case .overlap(let a, let b):
            let shared = draft.keys(for: a).intersection(draft.keys(for: b))
            return "\(a.label) and \(b.label) share \(shared.symbol)"
        }
    }
}
