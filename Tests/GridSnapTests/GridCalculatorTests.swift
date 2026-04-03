import Testing
import CoreGraphics
@testable import GridSnap

// MARK: - Helpers

private func approxEqual(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(a - b) < tolerance
}

private func approxEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.001) -> Bool {
    approxEqual(a.origin.x, b.origin.x, tolerance: tolerance) &&
    approxEqual(a.origin.y, b.origin.y, tolerance: tolerance) &&
    approxEqual(a.width,    b.width,    tolerance: tolerance) &&
    approxEqual(a.height,   b.height,   tolerance: tolerance)
}

// MARK: - Tests

@Test func basicThreeByThreeGrid() {
    // 1800 x 1200 screen, no gap, no padding → each cell is 600 x 400
    let frame  = CGRect(x: 0, y: 0, width: 1800, height: 1200)
    let config = GridConfiguration(rows: 3, cols: 3, gap: 0, padding: 0)
    let cells  = GridCalculator.cells(for: frame, configuration: config)

    #expect(cells.count == 3)
    #expect(cells[0].count == 3)

    let cellW: CGFloat = 600
    let cellH: CGFloat = 400

    #expect(approxEqual(cells[0][0], CGRect(x: 0, y: 0, width: cellW, height: cellH)))
    #expect(approxEqual(cells[0][2], CGRect(x: 1200, y: 0, width: cellW, height: cellH)))
    #expect(approxEqual(cells[2][0], CGRect(x: 0, y: 800, width: cellW, height: cellH)))
    #expect(approxEqual(cells[2][2], CGRect(x: 1200, y: 800, width: cellW, height: cellH)))
}

@Test func gridWithGapAndPadding() {
    // 1000 x 900, 2 cols, 3 rows, gap=10, padding=20
    // usableW = 1000 - 40 - 10 = 950 → cellW = 475
    // usableH = 900  - 40 - 20 = 840 → cellH = 280
    let frame  = CGRect(x: 0, y: 0, width: 1000, height: 900)
    let config = GridConfiguration(rows: 3, cols: 2, gap: 10, padding: 20)
    let cells  = GridCalculator.cells(for: frame, configuration: config)

    #expect(cells.count == 3)
    #expect(cells[0].count == 2)

    let cellW: CGFloat = 475
    let cellH: CGFloat = 280

    // Cell [0][0]: top-left, starts at padding
    #expect(approxEqual(cells[0][0].origin.x, 20))
    #expect(approxEqual(cells[0][0].origin.y, 20))
    #expect(approxEqual(cells[0][0].width, cellW))
    #expect(approxEqual(cells[0][0].height, cellH))

    // Cell [0][1]: second column — x = 20 + 475 + 10 = 505
    #expect(approxEqual(cells[0][1].origin.x, 505))

    // Cell [1][0]: second row — y = 20 + 280 + 10 = 310
    #expect(approxEqual(cells[1][0].origin.y, 310))
}

@Test func singleCellGridEqualsFullFrame() {
    let frame  = CGRect(x: 50, y: 100, width: 800, height: 600)
    let config = GridConfiguration(rows: 1, cols: 1, gap: 0, padding: 0)
    let cells  = GridCalculator.cells(for: frame, configuration: config)

    #expect(cells.count == 1)
    #expect(cells[0].count == 1)
    #expect(approxEqual(cells[0][0], frame))
}

@Test func firstCellStartsAtPadding() {
    let frame   = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let padding: CGFloat = 16
    let config  = GridConfiguration(rows: 2, cols: 4, gap: 8, padding: padding)
    let cells   = GridCalculator.cells(for: frame, configuration: config)

    #expect(approxEqual(cells[0][0].origin.x, padding))
    #expect(approxEqual(cells[0][0].origin.y, padding))
}

@Test func lastCellEndsAtFrameEdgeMinusPadding() {
    let frame   = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let padding: CGFloat = 16
    let config  = GridConfiguration(rows: 2, cols: 4, gap: 8, padding: padding)
    let cells   = GridCalculator.cells(for: frame, configuration: config)

    let lastRow = cells.last!
    let lastCell = lastRow.last!

    #expect(approxEqual(lastCell.maxX, frame.width  - padding))
    #expect(approxEqual(lastCell.maxY, frame.height - padding))
}

@Test func nonZeroFrameOrigin() {
    // Screens may not start at (0,0) in multi-monitor setups.
    let frame  = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
    let config = GridConfiguration(rows: 2, cols: 2, gap: 0, padding: 0)
    let cells  = GridCalculator.cells(for: frame, configuration: config)

    // Top-left cell should start at the frame's own origin.
    #expect(approxEqual(cells[0][0].origin.x, 2560))
    #expect(approxEqual(cells[0][0].origin.y, 0))
}
