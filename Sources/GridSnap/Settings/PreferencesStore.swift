import SwiftUI

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @AppStorage("gridRows") var rows: Int = 3
    @AppStorage("gridCols") var cols: Int = 3
    @AppStorage("gridGap") var gap: Double = 0
    @AppStorage("gridPadding") var padding: Double = 0
    @AppStorage("onboardingCompleted") var onboardingCompleted: Bool = false
    @AppStorage("isEnabled") var isEnabled: Bool = true

    /// Mirrors the SMAppService login item state. Setting this registers/unregisters the app.
    var launchAtLogin: Bool {
        get { LoginItemHelper.isEnabled }
        set { LoginItemHelper.setEnabled(newValue) }
    }

    var gridConfiguration: GridConfiguration {
        GridConfiguration(
            rows: rows,
            cols: cols,
            gap: CGFloat(gap),
            padding: CGFloat(padding)
        )
    }

    func applyPreset(_ config: GridConfiguration) {
        objectWillChange.send()
        rows = config.rows
        cols = config.cols
        gap = Double(config.gap)
        padding = Double(config.padding)
    }
}
