import Foundation

extension KeyboardSnapCoordinator {

    /// Cardinal directions supported by the keyboard snap shortcuts.
    /// Initialized from a raw macOS arrow-key virtual keycode; other
    /// keycodes are not sniq gestures and return `nil`.
    enum Direction {
        case up, down, left, right

        init?(keyCode: Int64) {
            switch keyCode {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            default:  return nil
            }
        }

        /// Returns the cell adjacent to `cell` in this direction, or
        /// `nil` if already at the grid boundary.
        func adjacent(from cell: GridCell, rows: Int, cols: Int) -> GridCell? {
            var newRow = cell.row
            var newCol = cell.col
            switch self {
            case .up:    newRow -= 1
            case .down:  newRow += 1
            case .left:  newCol -= 1
            case .right: newCol += 1
            }
            guard newRow >= 0, newRow < rows, newCol >= 0, newCol < cols else { return nil }
            return GridCell(row: newRow, col: newCol)
        }
    }
}
