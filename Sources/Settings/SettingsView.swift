import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var launchAtLogin = LoginItemHelper.isEnabled

    var body: some View {
        VStack(spacing: 16) {
            Text("Sniq Settings")
                .font(.headline)

            LayoutEditor(
                title: "Primary layout (Shift)",
                rows: $prefs.primaryRows,
                cols: $prefs.primaryCols
            )

            LayoutEditor(
                title: "Secondary layout (Shift + Ctrl)",
                rows: $prefs.secondaryRows,
                cols: $prefs.secondaryCols
            )

            Toggle("Keyboard shortcuts (Shift + Opt + Arrow)", isOn: $prefs.keyboardSnapEnabled)
                .font(.subheadline)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.subheadline)
                .onChange(of: launchAtLogin) {
                    LoginItemHelper.setEnabled(launchAtLogin)
                }
        }
        .padding(20)
        .frame(width: 320)
    }
}

// MARK: - Per-layout editor

private struct LayoutEditor: View {
    let title: String
    @Binding var rows: Int
    @Binding var cols: Int

    var body: some View {
        GroupBox(title) {
            VStack(spacing: 10) {
                HStack {
                    Text("Rows")
                    Spacer()
                    Stepper("\(rows)", value: $rows, in: 1...10)
                }
                HStack {
                    Text("Columns")
                    Spacer()
                    Stepper("\(cols)", value: $cols, in: 1...10)
                }
                GridPreview(rows: rows, cols: cols)
                    .frame(height: 80)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Preview widget

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
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

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
