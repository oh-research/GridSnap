@preconcurrency import Cocoa

/// Single-slot cache of the most recently computed grid cells.
///
/// Keyboard snap almost always targets the same screen + layout variant
/// + configuration in sequence (e.g., repeated arrow presses on a single
/// monitor), so a one-entry cache hits on the common case without growing
/// unboundedly. Multi-monitor or variant-switch workflows pay exactly one
/// extra `GridCalculator.cells` computation on the next press.
///
/// Main-actor isolated because `NSScreen` and `PreferencesStore` are.
@MainActor
final class GridCellsCache {

    private var cached: (key: Key, cells: [[CGRect]])?

    /// Returns the cached grid if the screen + config match the last call,
    /// otherwise recomputes and stores.
    func cells(
        for screen: NSScreen,
        variant: LayoutVariant,
        config: GridConfiguration
    ) -> [[CGRect]] {
        let key = Key(
            screenFrame: screen.visibleFrameCG,
            variant: variant,
            rows: config.rows,
            cols: config.cols,
            gap: config.gap,
            padding: config.padding
        )
        if let cached, cached.key == key {
            return cached.cells
        }
        let computed = GridCalculator.cells(for: screen.visibleFrameCG, configuration: config)
        cached = (key, computed)
        return computed
    }

    /// Drops the cached entry. Called on coordinator teardown so a later
    /// re-wire starts from a clean slate.
    func clear() {
        cached = nil
    }

    private struct Key: Equatable {
        let screenFrame: CGRect
        let variant: LayoutVariant
        let rows: Int
        let cols: Int
        let gap: CGFloat
        let padding: CGFloat
    }
}
