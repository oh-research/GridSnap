import SwiftUI

/// About window contents. Shows the app icon, name, version + build, author,
/// and a link to the source repository. Mirrors the visual style of the
/// "How to Use..." window so users see a consistent two-window pattern.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            AppIconView()
                .frame(width: 96, height: 96)

            Text("Sniq")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 6) {
                Text("Version \(versionString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Developed by oh-research")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Link(
                    "github.com/oh-research/Sniq",
                    destination: URL(string: "https://github.com/oh-research/Sniq")!
                )
                .font(.caption)
            }

            Spacer(minLength: 0)

            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(28)
        .frame(width: 320, height: 340)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (build \(build))"
    }
}
