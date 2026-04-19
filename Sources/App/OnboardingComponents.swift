import SwiftUI

// MARK: - How-to row

struct HowToRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Onboarding progress

struct OnboardingStep {
    let title: String
    let completed: Bool
}

struct OnboardingProgressView: View {
    let steps: [OnboardingStep]

    private var currentIndex: Int {
        steps.firstIndex(where: { !$0.completed }) ?? steps.count
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                StepDot(
                    number: index + 1,
                    title: step.title,
                    completed: step.completed,
                    isCurrent: index == currentIndex
                )
                if index < steps.count - 1 {
                    connector(active: step.completed)
                }
            }
        }
    }

    private func connector(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Color.green : Color.secondary.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22) // vertical-center against the dot (not the label)
            .animation(.easeInOut(duration: 0.3), value: active)
    }
}

private struct StepDot: View {
    let number: Int
    let title: String
    let completed: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .stroke(Color.accentColor.opacity(isCurrent ? 0.35 : 0), lineWidth: 4)
            )
            .animation(.easeInOut(duration: 0.25), value: completed)

            Text(title)
                .font(.caption)
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }

    private var backgroundColor: Color {
        if completed { return .green }
        if isCurrent { return .accentColor }
        return Color.secondary.opacity(0.3)
    }
}

// MARK: - Permission card

struct PermissionCardView: View {
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    let primaryAction: () -> Void
    let fallbackAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconBadge
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    StatusBadge(granted: granted)
                }
                Text(granted ? "Permission granted" : description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !granted {
                    HStack(spacing: 10) {
                        // Custom style keeps the accent fill + white text
                        // regardless of window focus. .borderedProminent
                        // fades so aggressively when the window deactivates
                        // that the button effectively disappears.
                        Button(action: primaryAction) {
                            Label("Grant Access", systemImage: "arrow.up.forward.square")
                        }
                        .buttonStyle(AccentFillButtonStyle())

                        if let fallbackAction {
                            Button("Open Settings", action: fallbackAction)
                                .buttonStyle(.link)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: granted)
    }

    private var iconBadge: some View {
        ZStack {
            Circle().fill(iconBackgroundColor)
            Image(systemName: granted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(iconForegroundColor)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: granted)
    }

    private var iconBackgroundColor: Color {
        (granted ? Color.green : Color.orange).opacity(0.15)
    }

    private var iconForegroundColor: Color {
        granted ? .green : .orange
    }

    private var borderColor: Color {
        (granted ? Color.green : Color.orange).opacity(0.3)
    }
}

private struct StatusBadge: View {
    let granted: Bool

    var body: some View {
        Text(granted ? "Granted" : "Required")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(granted ? .green : .orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill((granted ? Color.green : Color.orange).opacity(0.15))
            )
    }
}

/// Solid-accent button style that does not dim when the window loses focus,
/// unlike `.borderedProminent` which fades aggressively. Matches the visual
/// weight of the default-action Close/Get Started button.
private struct AccentFillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
    }
}
