import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var launchAtLogin = LoginItemHelper.isEnabled

    var body: some View {
        VStack(spacing: 16) {
            LayoutEditor(
                title: "Primary layout (\(prefs.bindings.grip.formatted))",
                rows: $prefs.primaryRows,
                cols: $prefs.primaryCols
            )

            LayoutEditor(
                title: "Secondary layout (\(prefs.bindings.grip.formatted) + \(prefs.bindings.flip.formatted))",
                rows: $prefs.secondaryRows,
                cols: $prefs.secondaryCols
            )

            GroupBox("Modifier bindings") {
                ModifierBindingView()
            }

            HStack(spacing: 8) {
                ToggleTile(
                    title: "Keyboard\nshortcut",
                    isOn: $prefs.keyboardSnapEnabled
                )
                ToggleTile(
                    title: "Intercept\nin text fields",
                    isOn: $prefs.interceptInTextFields,
                    enabled: prefs.keyboardSnapEnabled
                )
                ToggleTile(
                    title: "Launch\nat login",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) {
                    LoginItemHelper.setEnabled(launchAtLogin)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

// MARK: - Toggle tile

/// Tall two-line toggle button used by the Settings footer row.
/// Active state is signalled by a blue border overlay rather than a
/// filled background — easier on the eyes than solid accent fill.
private struct ToggleTile: View {
    let title: String
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .disabled(!enabled)
    }
}

// MARK: - Per-layout editor

private struct LayoutEditor: View {
    let title: String
    @Binding var rows: Int
    @Binding var cols: Int

    var body: some View {
        GroupBox {
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
        } label: {
            Text(verbatim: title)
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
