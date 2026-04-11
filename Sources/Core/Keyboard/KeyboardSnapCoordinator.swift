@preconcurrency import Cocoa

/// Handles `Shift+Opt+Arrow` (Primary) and `Shift+Ctrl+Opt+Arrow` (Secondary)
/// keyboard shortcuts by moving the focused window to the adjacent grid cell
/// in the requested direction. Entirely independent from the drag pipeline;
/// shares layout configuration via `PreferencesStore` and snap math via
/// `GridCalculator` / `SnapResolver` / `WindowManipulator`.
///
/// Wiring: `DragCoordinator.start()` calls `wire(to:)` so the coordinator
/// installs a synchronous keyboard handler on the existing `EventMonitor`
/// tap. The handler decides suppression (event tap budget ~1 ms) and
/// schedules the actual snap on the main actor.
final class KeyboardSnapCoordinator: @unchecked Sendable {

    static let shared = KeyboardSnapCoordinator()

    private init() {}

    // MARK: - Wiring

    /// Installs the synchronous keyboard handler on the event monitor.
    /// The handler is invoked on the CGEventTap thread and must return
    /// within the tap budget.
    func wire(to monitor: EventMonitor) {
        monitor.keyboardHandler = { [weak self] keyCode, shift, ctrl, opt in
            guard let self else { return false }
            return self.shouldSuppress(keyCode: keyCode, shift: shift, ctrl: ctrl, opt: opt)
        }
    }

    // MARK: - Sync entry (CGEventTap callback thread)

    /// Returns `true` if the event was claimed by Sniq (suppress it);
    /// `false` to pass it through to the system (text editing, feature off,
    /// non-Sniq shortcut).
    private func shouldSuppress(keyCode: Int64, shift: Bool, ctrl: Bool, opt: Bool) -> Bool {
        guard let direction = Direction(keyCode: keyCode) else { return false }
        guard shift && opt else { return false }
        guard isEnabled else { return false }
        if FocusedWindowDetector.isTextElementFocused() { return false }

        let useSecondary = ctrl
        DispatchQueue.main.async { [weak self] in
            self?.performSnap(direction: direction, useSecondary: useSecondary)
        }
        return true
    }

    // MARK: - Snap execution (main actor)

    @MainActor
    private func performSnap(direction: Direction, useSecondary: Bool) {
        guard let window = FocusedWindowDetector.focusedWindow() else { return }
        guard let currentFrame = FocusedWindowDetector.frame(of: window) else { return }
        guard let screen = FocusedWindowDetector.screen(containing: currentFrame) else { return }

        let variant: LayoutVariant = useSecondary ? .secondary : .primary
        let config = PreferencesStore.shared.configuration(for: variant)
        let cells = GridCalculator.cells(for: screen.visibleFrameCG, configuration: config)

        let resolver = SnapResolver(cells: cells)
        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        guard let currentCell = resolver.cell(at: center) else { return }

        guard let nextCell = Self.adjacentCell(
            from: currentCell,
            direction: direction,
            rows: config.rows,
            cols: config.cols
        ) else { return }  // Boundary → no-op

        let targetRect = cells[nextCell.row][nextCell.col]
        WindowManipulator.shared.setFrame(targetRect, for: window)
    }

    // MARK: - Pure helpers

    private static func adjacentCell(
        from cell: GridCell,
        direction: Direction,
        rows: Int,
        cols: Int
    ) -> GridCell? {
        var newRow = cell.row
        var newCol = cell.col
        switch direction {
        case .up:    newRow -= 1
        case .down:  newRow += 1
        case .left:  newCol -= 1
        case .right: newCol += 1
        }
        guard newRow >= 0, newRow < rows, newCol >= 0, newCol < cols else { return nil }
        return GridCell(row: newRow, col: newCol)
    }

    // MARK: - Feature flag

    /// Read directly from UserDefaults so the event tap thread can query
    /// without hopping to the main actor.
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "keyboardSnapEnabled")
    }
}

// MARK: - Direction

extension KeyboardSnapCoordinator {
    enum Direction {
        case up, down, left, right

        /// macOS arrow key virtual keycodes.
        init?(keyCode: Int64) {
            switch keyCode {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            default:  return nil
            }
        }
    }
}
