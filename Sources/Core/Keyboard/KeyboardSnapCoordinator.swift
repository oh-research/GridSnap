@preconcurrency import Cocoa

/// Handles the `Shift+Opt+Arrow` (primary-layout) keyboard shortcut by
/// moving the focused window to the adjacent grid cell in the requested
/// direction. Secondary-layout and disambiguation features were removed
/// after proving too complex to stabilize across multi-monitor and
/// rapid-fire scenarios — the basic primary navigation is kept simple
/// and reliable.
///
/// Lifecycle: `DragCoordinator.start()` calls `wire(to:)`, which installs
/// the keyboard handler on the shared `EventMonitor` and starts
/// `TextFocusMonitor` / `FocusedWindowCache`. `DragCoordinator.stop()`
/// calls `unwire(from:)` to tear those down symmetrically.
final class KeyboardSnapCoordinator: @unchecked Sendable {

    static let shared = KeyboardSnapCoordinator()

    private init() {}

    @MainActor private let gridCache = GridCellsCache()

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
        gridCache.clear()
    }

    // MARK: - Sync entry (CGEventTap callback thread)

    /// Returns `true` if the event was claimed by Sniq (suppress it);
    /// `false` to pass it through to the system.
    private func shouldSuppress(keyCode: Int64, modifiers: PressedModifiers) -> Bool {
        guard let direction = Direction(keyCode: keyCode) else { return false }
        guard isEnabled else { return false }
        let bindings = ModifierBindings.load()
        // Only the primary variant is bound to a keyboard shortcut. The
        // secondary variant is reachable via drag snap (different flow).
        guard let variant = bindings.keyboardVariant(pressed: modifiers),
              variant == .primary
        else { return false }
        if !interceptInTextFields && TextFocusMonitor.shared.isTextFocused {
            return false
        }
        guard let window = FocusedWindowCache.shared.focusedWindow else { return false }

        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
            self?.performSnap(window: window, direction: direction)
        }
        return true
    }

    // MARK: - Snap execution (main actor)

    @MainActor
    private func performSnap(window: AXUIElement, direction: Direction) {
        guard let currentFrame = FocusedWindowDetector.frame(of: window) else {
            // Window was closed between key press and execution — drop
            // stale cache so the next press fetches fresh.
            FocusedWindowCache.shared.invalidate()
            return
        }
        guard let screen = FocusedWindowDetector.screen(containing: currentFrame) else { return }

        let config = PreferencesStore.shared.configuration(for: .primary)
        let cells = gridCache.cells(for: screen, variant: .primary, config: config)

        let resolver = SnapResolver(cells: cells)
        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        guard let currentCell = resolver.cell(at: center) else { return }

        // On boundary (no adjacent cell in the requested direction), fall
        // back to the current cell so the window re-fits exactly when the
        // layout config has changed.
        let targetCell = direction.adjacent(
            from: currentCell, rows: config.rows, cols: config.cols
        ) ?? currentCell

        let targetRect = cells[targetCell.row][targetCell.col]
        if Self.framesApproximatelyEqual(currentFrame, targetRect) { return }
        WindowManipulator.shared.setFrame(targetRect, for: window)
    }

    /// Two frames are considered identical if every component is within
    /// 1 pt. Grid cells are integer-pixel, so anything larger than this
    /// tolerance reflects a real layout mismatch worth re-snapping.
    private static func framesApproximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) <= 1 &&
        abs(a.origin.y - b.origin.y) <= 1 &&
        abs(a.size.width - b.size.width) <= 1 &&
        abs(a.size.height - b.size.height) <= 1
    }

    // MARK: - Feature flag

    /// Read directly from UserDefaults so the event tap thread can query
    /// without hopping to the main actor.
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "keyboardSnapEnabled")
    }

    /// When `true`, keyboard shortcuts fire even when a text field has
    /// focus (overriding macOS's native word-selection on Shift+Opt+Arrow).
    /// Defaults to `false`. `UserDefaults.bool` returns `false` for unset
    /// keys which matches the intended default.
    private var interceptInTextFields: Bool {
        UserDefaults.standard.bool(forKey: "keyboardSnapInterceptInTextFields")
    }
}
