@preconcurrency import Cocoa

/// Manages a transparent, click-through overlay window drawn on top of a single screen.
/// All methods must be called on the main thread.
@MainActor
final class OverlayWindowController {

    // MARK: - Properties

    private(set) var overlayWindow: NSWindow?
    private(set) var overlayView: GridOverlayView?

    // MARK: - Show / hide

    /// Creates (if needed) and shows the overlay on the given screen, reconfiguring the grid.
    func show(on screen: NSScreen, gridCells: [[CGRect]]) {
        let screenFrame = screen.frame   // Cocoa (bottom-left) frame for NSWindow

        if overlayWindow == nil {
            let window = makeWindow(frame: screenFrame)
            let view   = GridOverlayView(frame: CGRect(origin: .zero, size: screenFrame.size))
            window.contentView = view
            overlayWindow = window
            overlayView   = view
        } else {
            overlayWindow?.setFrame(screenFrame, display: false)
            if let view = overlayView {
                view.frame = CGRect(origin: .zero, size: screenFrame.size)
            }
        }

        overlayView?.gridCells = gridCells
        overlayWindow?.orderFrontRegardless()
    }

    /// Hides the overlay window without destroying it.
    func hide() {
        overlayWindow?.orderOut(nil)
    }

    // MARK: - Highlight updates

    /// Highlights a single cell.
    func updateHighlight(cell: GridCell) {
        overlayView?.highlightedCells = [cell]
    }

    /// Highlights all cells in the rectangle spanned by `from` and `to`.
    func updateHighlight(region from: GridCell, to: GridCell) {
        guard let cells = overlayView?.gridCells,
              !cells.isEmpty else { return }

        let rows = cells.count
        let cols = cells[0].count

        let minRow = min(from.row, to.row)
        let maxRow = min(max(from.row, to.row), rows - 1)
        let minCol = min(from.col, to.col)
        let maxCol = min(max(from.col, to.col), cols - 1)

        var highlighted = Set<GridCell>()
        for r in minRow ... maxRow {
            for c in minCol ... maxCol {
                highlighted.insert(GridCell(row: r, col: c))
            }
        }
        overlayView?.highlightedCells = highlighted
    }

    // MARK: - Private helpers

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )
        window.backgroundColor   = .clear
        window.isOpaque          = false
        window.hasShadow         = false
        window.ignoresMouseEvents = true
        window.level             = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return window
    }
}
