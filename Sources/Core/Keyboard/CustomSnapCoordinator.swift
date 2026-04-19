@preconcurrency import Cocoa

/// Routes key-down events to saved `Snapshot`s. Match happens in the
/// `CGEventTap` callback via `SnapshotStore.lookup` (lock-protected),
/// then the actual window move hops to the main actor.
///
/// Lifecycle: `DragCoordinator.start()` calls `wire(to:)` — this installs
/// the keyboard handler on the shared `EventMonitor` and starts the
/// `TextFocusMonitor` / `FocusedWindowCache` helpers. `DragCoordinator.stop()`
/// calls `unwire(from:)` to tear those down symmetrically.
final class CustomSnapCoordinator: @unchecked Sendable {

    static let shared = CustomSnapCoordinator()

    private init() {}

    // MARK: - Wiring

    func wire(to monitor: EventMonitor) {
        TextFocusMonitor.shared.start()
        FocusedWindowCache.shared.start()
        monitor.keyboardHandler = { [weak self] keyCode, modifiers in
            guard let self else { return false }
            return self.shouldSuppress(keyCode: keyCode, modifiers: modifiers)
        }
    }

    @MainActor
    func unwire(from monitor: EventMonitor) {
        monitor.keyboardHandler = nil
        FocusedWindowCache.shared.stop()
        TextFocusMonitor.shared.stop()
    }

    // MARK: - Event-tap entry

    /// Returns `true` when Sniq claims the key event (suppress); `false`
    /// to pass it through. Runs on the tap callback thread — every branch
    /// must return within the ~1 ms budget.
    private func shouldSuppress(keyCode: Int64, modifiers: PressedModifiers) -> Bool {
        guard UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true else {
            return false
        }
        // macOS flips the fn bit on arrow-key events even when the user
        // hasn't touched fn; strip it so stored shortcuts match.
        let normalized = modifiers.subtracting(.function)
        guard let snapshot = SnapshotLookupMirror.shared.lookup(
            keyCode: keyCode, modifiers: normalized
        ) else {
            return false
        }
        // Yield to text input so users can still type, select words
        // with ⇧⌥Arrow, etc. sniq deliberately loses this race.
        if TextFocusMonitor.shared.isTextFocused { return false }
        guard let window = FocusedWindowCache.shared.focusedWindow else { return false }

        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
            self?.performSnap(snapshot: snapshot, window: window)
        }
        return true
    }

    // MARK: - Snap execution (main actor)

    @MainActor
    private func performSnap(snapshot: Snapshot, window: AXUIElement) {
        guard let currentFrame = FocusedWindowDetector.frame(of: window) else {
            FocusedWindowCache.shared.invalidate()
            return
        }
        guard let screen = FocusedWindowDetector.screen(containing: currentFrame) else { return }

        let spec = snapshot.spec
        let prefs = PreferencesStore.shared
        let config = GridConfiguration(
            rows: spec.rows,
            cols: spec.cols,
            gap: CGFloat(prefs.gap),
            padding: CGFloat(prefs.padding)
        )
        let cells = GridCalculator.cells(
            for: screen.visibleFrameCG, configuration: config
        )
        guard
            spec.minCell.row >= 0, spec.minCell.col >= 0,
            spec.maxCell.row < cells.count,
            !cells.isEmpty,
            spec.maxCell.col < cells[0].count
        else { return }

        let topLeft     = cells[spec.minCell.row][spec.minCell.col]
        let bottomRight = cells[spec.maxCell.row][spec.maxCell.col]
        let targetRect  = topLeft.union(bottomRight)

        WindowManipulator.shared.setFrame(targetRect, for: window)
    }
}
