import SwiftUI

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @AppStorage("primaryRows") var primaryRows: Int = 2
    @AppStorage("primaryCols") var primaryCols: Int = 3
    @AppStorage("secondaryRows") var secondaryRows: Int = 3
    @AppStorage("secondaryCols") var secondaryCols: Int = 2
    @AppStorage("gridGap") var gap: Double = 0
    @AppStorage("gridPadding") var padding: Double = 0
    @AppStorage("onboardingCompleted") var onboardingCompleted: Bool = false
    @AppStorage("isEnabled") var isEnabled: Bool = true
    @AppStorage("keyboardSnapEnabled") var keyboardSnapEnabled: Bool = false

    /// Mirrors the SMAppService login item state. Setting this registers/unregisters the app.
    var launchAtLogin: Bool {
        get { LoginItemHelper.isEnabled }
        set { LoginItemHelper.setEnabled(newValue) }
    }

    private init() {
        Self.migrateLegacyGridKeysIfNeeded()
    }

    /// Returns the grid configuration for the given variant. `gap` and
    /// `padding` are shared across layouts.
    func configuration(for variant: LayoutVariant) -> GridConfiguration {
        switch variant {
        case .primary:
            return GridConfiguration(
                rows: primaryRows,
                cols: primaryCols,
                gap: CGFloat(gap),
                padding: CGFloat(padding)
            )
        case .secondary:
            return GridConfiguration(
                rows: secondaryRows,
                cols: secondaryCols,
                gap: CGFloat(gap),
                padding: CGFloat(padding)
            )
        }
    }

    // MARK: - Legacy migration

    /// Migrates pre-v1.1.0 `gridRows`/`gridCols` into the new primary/secondary
    /// keys on first launch after upgrade. Secondary is initialized as the
    /// row/col swap of the legacy value so users immediately see a meaningful
    /// difference when holding Opt. Legacy keys are left in place as a rollback
    /// safety net.
    private static func migrateLegacyGridKeysIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "primaryRows") == nil else { return }

        let legacyRows = (defaults.object(forKey: "gridRows") as? Int) ?? 2
        let legacyCols = (defaults.object(forKey: "gridCols") as? Int) ?? 3

        defaults.set(legacyRows, forKey: "primaryRows")
        defaults.set(legacyCols, forKey: "primaryCols")
        defaults.set(legacyCols, forKey: "secondaryRows")
        defaults.set(legacyRows, forKey: "secondaryCols")
    }
}
