@preconcurrency import Cocoa

// MARK: - Grid

struct GridCell: Equatable, Hashable, Sendable {
    let row: Int
    let col: Int
}

struct GridConfiguration: Equatable, Sendable {
    var rows: Int
    var cols: Int
    var gap: CGFloat
    var padding: CGFloat

    static let `default` = GridConfiguration(rows: 2, cols: 3, gap: 0, padding: 0)

    static let presets: [(name: String, config: GridConfiguration)] = [
        ("2x2", GridConfiguration(rows: 2, cols: 2, gap: 0, padding: 0)),
        ("2x3", GridConfiguration(rows: 2, cols: 3, gap: 0, padding: 0)),
        ("2x4", GridConfiguration(rows: 2, cols: 4, gap: 0, padding: 0)),
    ]
}

// MARK: - Window

struct TrackedWindow: @unchecked Sendable {
    let windowID: CGWindowID
    let axElement: AXUIElement
    let pid: pid_t
    let originalFrame: CGRect
}

// MARK: - Drag State

enum DragState: Sendable {
    case idle
    case potentialDrag(mouseDownPos: CGPoint, windowID: CGWindowID, pid: pid_t)
    case shiftDragging(trackedWindow: TrackedWindow, currentCell: GridCell?)
    case multiCellSelecting(trackedWindow: TrackedWindow, anchorCell: GridCell, currentCell: GridCell?)
    case snapping(trackedWindow: TrackedWindow, targetRect: CGRect)
}
