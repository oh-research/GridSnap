import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @ObservedObject private var prefs = PreferencesStore.shared

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                AppIconView()
                    .frame(width: 96, height: 96)

                Text("GridSnap")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Developed by oh-research")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Link("github.com/oh-research/GridSnap",
                     destination: URL(string: "https://github.com/oh-research/GridSnap")!)
                    .font(.caption)
            }

            Divider()

            // How to use
            GroupBox("How to use") {
                VStack(alignment: .leading, spacing: 10) {
                    HowToRow(
                        icon: "arrow.up.and.down.and.arrow.left.and.right",
                        text: "Hold Shift and drag a window title bar"
                    )
                    HowToRow(
                        icon: "grid",
                        text: "A grid overlay appears on screen"
                    )
                    HowToRow(
                        icon: "arrow.down.to.line",
                        text: "Release to snap the window to the highlighted cell"
                    )
                    HowToRow(
                        icon: "escape",
                        text: "Release Shift or press Escape to cancel"
                    )
                }
                .padding(.vertical, 4)
            }

            // Permissions
            GroupBox("Permissions") {
                VStack(spacing: 12) {
                    // Accessibility
                    PermissionRow(
                        granted: accessibility.isTrusted,
                        title: "Accessibility",
                        description: "Required to move and resize windows",
                        action: { accessibility.requestPermission() }
                    )

                    Divider()

                    // Input Monitoring
                    PermissionRow(
                        granted: accessibility.canListenEvents,
                        title: "Input Monitoring",
                        description: "Required to detect Shift + drag gestures",
                        action: { accessibility.openInputMonitoringSettings() }
                    )
                }
                .padding(.vertical, 4)
            }

            // Done
            Button("Get Started") {
                prefs.onboardingCompleted = true
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!accessibility.allPermissionsGranted)
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            accessibility.checkPermission()
            accessibility.startPolling()
        }
    }
}

struct PermissionRow: View {
    let granted: Bool
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(granted ? "Permission granted" : description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("Grant Access") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

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
