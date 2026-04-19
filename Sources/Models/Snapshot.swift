import Foundation

// MARK: - SnapSpec

/// The geometric half of a snapshot: which grid, which rectangular region.
/// Shared by `SnapHistory` entries (no shortcut yet) and saved `Snapshot`s
/// (with shortcut). `minCell == maxCell` means a single-cell snap.
struct SnapSpec: Codable, Equatable, Hashable, Sendable {
    var rows: Int
    var cols: Int
    var minCell: GridCell
    var maxCell: GridCell

    /// Normalizes so `minCell <= maxCell` component-wise. `GripDragCoordinator`
    /// already passes anchor/current in either order when the user drags up
    /// or left, so callers should funnel through this.
    init(rows: Int, cols: Int, anchor: GridCell, current: GridCell) {
        self.rows = rows
        self.cols = cols
        self.minCell = GridCell(
            row: min(anchor.row, current.row),
            col: min(anchor.col, current.col)
        )
        self.maxCell = GridCell(
            row: max(anchor.row, current.row),
            col: max(anchor.col, current.col)
        )
    }

    /// Raw initializer for decoded values.
    init(rows: Int, cols: Int, minCell: GridCell, maxCell: GridCell) {
        self.rows = rows
        self.cols = cols
        self.minCell = minCell
        self.maxCell = maxCell
    }

    /// Human-readable summary for UI: `"3×2 · (0,0)→(0,1)"` or `"2×2 · (1,1)"`.
    var summary: String {
        let grid = "\(rows)×\(cols)"
        if minCell == maxCell {
            return "\(grid) · (\(minCell.row),\(minCell.col))"
        }
        return "\(grid) · (\(minCell.row),\(minCell.col))→(\(maxCell.row),\(maxCell.col))"
    }
}

// MARK: - Snapshot

/// A saved snapshot: geometry + a keyboard shortcut that recalls it.
/// Persisted by `SnapshotStore`, matched on the event-tap thread to
/// move the frontmost window into `spec`'s region on the active screen.
struct Snapshot: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var spec: SnapSpec
    var shortcut: ShortcutSpec

    init(id: UUID = UUID(), spec: SnapSpec, shortcut: ShortcutSpec) {
        self.id = id
        self.spec = spec
        self.shortcut = shortcut
    }
}
