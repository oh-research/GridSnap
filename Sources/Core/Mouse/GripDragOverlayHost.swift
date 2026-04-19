@preconcurrency import Cocoa

/// Owns the overlay controllers, current grid, and snap resolver for the
/// Grip+drag gesture. Isolated from `GripDragCoordinator` so that file
/// stays focused on state-machine and event-handling concerns.
///
/// All methods are main-actor because the wrapped `OverlayWindowController`
/// touches NSWindow which is main-actor-only.
@MainActor
final class GripDragOverlayHost {

    private var controllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var active: OverlayWindowController?
    private(set) var activeScreen: NSScreen?
    private(set) var gridCells: [[CGRect]] = []
    private var resolver: SnapResolver?

    // MARK: - Show / hide

    func show(on screen: NSScreen, variant: LayoutVariant) {
        rebuildGrid(for: screen, variant: variant)
        let controller = controller(for: screen)
        if let previous = active, previous !== controller {
            previous.hide()
        }
        active = controller
        controller.show(on: screen, gridCells: viewLocalCells(for: screen))
    }

    func hide() {
        active?.hide()
        active = nil
        gridCells = []
        resolver = nil
        activeScreen = nil
    }

    /// Current grid shape — populated after `show(on:variant:)` builds the
    /// resolver. `(0, 0)` until then.
    var gridDimensions: (rows: Int, cols: Int) {
        (gridCells.count, gridCells.first?.count ?? 0)
    }

    // MARK: - Highlight

    func updateHighlight(cell: GridCell) { active?.updateHighlight(cell: cell) }

    func updateHighlight(region anchor: GridCell, to current: GridCell) {
        active?.updateHighlight(region: anchor, to: current)
    }

    // MARK: - Geometry

    func cell(at point: CGPoint) -> GridCell? { resolver?.cell(at: point) }

    func cellRect(at cell: GridCell) -> CGRect? {
        guard cell.row < gridCells.count, cell.col < gridCells[cell.row].count else { return nil }
        return gridCells[cell.row][cell.col]
    }

    func regionUnion(from anchor: GridCell, to current: GridCell) -> CGRect? {
        let minRow = min(anchor.row, current.row)
        let maxRow = max(anchor.row, current.row)
        let minCol = min(anchor.col, current.col)
        let maxCol = max(anchor.col, current.col)
        guard maxRow < gridCells.count, maxCol < gridCells[maxRow].count else { return nil }
        return gridCells[minRow][minCol].union(gridCells[maxRow][maxCol])
    }

    func screenContaining(point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.visibleFrameCG.insetBy(dx: -1, dy: -1).contains(point) {
                return screen
            }
        }
        return NSScreen.main
    }

    // MARK: - Private

    private func rebuildGrid(for screen: NSScreen, variant: LayoutVariant) {
        activeScreen = screen
        let config = PreferencesStore.shared.configuration(for: variant)
        gridCells = GridCalculator.cells(for: screen.visibleFrameCG, configuration: config)
        resolver = SnapResolver(cells: gridCells)
    }

    private func controller(for screen: NSScreen) -> OverlayWindowController {
        let id = screen.displayID ?? 0
        if let existing = controllers[id] { return existing }
        let controller = OverlayWindowController()
        controllers[id] = controller
        return controller
    }

    private func viewLocalCells(for screen: NSScreen) -> [[CGRect]] {
        let origin = screen.fullFrameCG.origin
        return gridCells.map { row in
            row.map {
                CGRect(
                    x: $0.origin.x - origin.x,
                    y: $0.origin.y - origin.y,
                    width: $0.width,
                    height: $0.height
                )
            }
        }
    }
}
