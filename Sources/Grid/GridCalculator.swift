// GridCalculator.swift
// Pure logic — no UI dependencies. All coordinates are in CG coordinate system (top-left origin).
import CoreGraphics

struct GridCalculator {
    /// Computes a 2D array of cell CGRects for the given screen visible frame and grid configuration.
    /// - Parameters:
    ///   - frame: Screen visible frame in CG coordinates (top-left origin).
    ///   - configuration: Grid layout parameters (rows, cols, gap, padding).
    /// - Returns: `cells[row][col]` CGRect, row 0 is the top row.
    static func cells(for frame: CGRect, configuration: GridConfiguration) -> [[CGRect]] {
        let rows = max(1, configuration.rows)
        let cols = max(1, configuration.cols)
        let gap = max(0, configuration.gap)
        let padding = max(0, configuration.padding)

        let usableWidth  = frame.width  - 2 * padding - CGFloat(cols - 1) * gap
        let usableHeight = frame.height - 2 * padding - CGFloat(rows - 1) * gap

        let cellW = usableWidth  / CGFloat(cols)
        let cellH = usableHeight / CGFloat(rows)

        var grid: [[CGRect]] = []
        grid.reserveCapacity(rows)

        for r in 0 ..< rows {
            var rowRects: [CGRect] = []
            rowRects.reserveCapacity(cols)
            for c in 0 ..< cols {
                let x = frame.minX + padding + CGFloat(c) * (cellW + gap)
                let y = frame.minY + padding + CGFloat(r) * (cellH + gap)
                rowRects.append(CGRect(x: x, y: y, width: cellW, height: cellH))
            }
            grid.append(rowRects)
        }

        return grid
    }
}
