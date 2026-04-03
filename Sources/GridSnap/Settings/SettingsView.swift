import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var launchAtLogin = LoginItemHelper.isEnabled

    var body: some View {
        VStack(spacing: 20) {
            Text("GridSnap Settings")
                .font(.headline)

            // Grid size
            GroupBox("Grid Size") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Rows")
                        Spacer()
                        Stepper("\(prefs.rows)", value: $prefs.rows, in: 1...10)
                    }
                    HStack {
                        Text("Columns")
                        Spacer()
                        Stepper("\(prefs.cols)", value: $prefs.cols, in: 1...10)
                    }
                }
                .padding(.vertical, 4)
            }

            // Presets
            GroupBox("Presets") {
                HStack(spacing: 8) {
                    ForEach(GridConfiguration.presets, id: \.name) { preset in
                        PresetButton(
                            name: preset.name,
                            isActive: prefs.rows == preset.config.rows
                                && prefs.cols == preset.config.cols
                        ) {
                            prefs.applyPreset(preset.config)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Launch at login
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.subheadline)
                .onChange(of: launchAtLogin) {
                    LoginItemHelper.setEnabled(launchAtLogin)
                }

            // Preview
            GroupBox("Preview") {
                GridPreview(rows: prefs.rows, cols: prefs.cols)
                    .frame(height: 120)
                    .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct GridPreview: View {
    let rows: Int
    let cols: Int

    var body: some View {
        GeometryReader { geo in
            let screenRatio: CGFloat = 16.0 / 10.0
            let previewHeight = geo.size.height
            let previewWidth = min(geo.size.width, previewHeight * screenRatio)

            let offsetX = (geo.size.width - previewWidth) / 2

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                // Grid lines
                Canvas { context, size in
                    let cellW = size.width / CGFloat(cols)
                    let cellH = size.height / CGFloat(rows)

                    for c in 1..<cols {
                        let x = CGFloat(c) * cellW
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
                    }
                    for r in 1..<rows {
                        let y = CGFloat(r) * cellH
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
                    }
                }
            }
            .frame(width: previewWidth, height: previewHeight)
            .offset(x: offsetX)
        }
    }
}

struct PresetButton: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(minWidth: 40)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
