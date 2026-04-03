import Testing
import CoreGraphics
@testable import GridSnap

// MARK: - Fixture

/// 3x3 grid on a 900x900 frame, no gap, no padding.
/// Each cell is 300x300.
private func makeSimpleResolver() -> SnapResolver {
    let frame  = CGRect(x: 0, y: 0, width: 900, height: 900)
    let config = GridConfiguration(rows: 3, cols: 3, gap: 0, padding: 0)
    let cells  = GridCalculator.cells(for: frame, configuration: config)
    return SnapResolver(cells: cells)
}

/// 3x3 grid with 10pt gap and 20pt padding on a 1000x1000 frame.
/// usableW = 1000 - 40 - 20 = 940 → cellW ≈ 313.33
/// usableH = 1000 - 40 - 20 = 940 → cellH ≈ 313.33
private func makeGappedResolver() -> SnapResolver {
    let frame  = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let config = GridConfiguration(rows: 3, cols: 3, gap: 10, padding: 20)
    let cells  = GridCalculator.cells(for: frame, configuration: config)
    return SnapResolver(cells: cells)
}

// MARK: - Tests

@Test func cursorInCenterOfCellResolvesCorrectly() {
    let resolver = makeSimpleResolver()

    // Center of cell [1][1] = (450, 450)
    let cell = resolver.cell(at: CGPoint(x: 450, y: 450))
    #expect(cell == GridCell(row: 1, col: 1))
}

@Test func cursorAtCellOriginResolvesCorrectCell() {
    let resolver = makeSimpleResolver()

    // Origin of cell [0][0] = (0, 0)
    let cell = resolver.cell(at: CGPoint(x: 0, y: 0))
    #expect(cell == GridCell(row: 0, col: 0))
}

@Test func cursorOnGapResolvesToAdjacentCell() {
    // 3x3 grid, 1000x1000, gap=10, padding=0
    // cellW = (1000 - 20) / 3 ≈ 326.67, effectiveCellW = 336.67
    // First gap region: x ∈ [326.67, 336.67)
    // A cursor at x=330 should resolve to col 0 (floor(330 / 336.67) = 0)
    let frame  = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let config = GridConfiguration(rows: 3, cols: 3, gap: 10, padding: 0)
    let cells  = GridCalculator.cells(for: frame, configuration: config)
    let resolver = SnapResolver(cells: cells)

    // Gap is between 326.67 and 336.67. Cursor at x=330 → col 0 (just past cell 0 edge but
    // before col 1 boundary in effectiveCellW units).
    let cell = resolver.cell(at: CGPoint(x: 330, y: 500))
    #expect(cell?.col == 0)
}

@Test func cursorAtGridTopLeftEdgeClampedToFirstCell() {
    let resolver = makeSimpleResolver()

    let cell = resolver.cell(at: CGPoint(x: 0, y: 0))
    #expect(cell == GridCell(row: 0, col: 0))
}

@Test func cursorAtGridBottomRightEdgeClampedToLastCell() {
    let resolver = makeSimpleResolver()

    // Exactly at the bottom-right corner (900,900) — still should clamp to last cell.
    let cell = resolver.cell(at: CGPoint(x: 900, y: 900))
    #expect(cell == GridCell(row: 2, col: 2))
}

@Test func cursorBeyondRightEdgeClampsToLastColumn() {
    let resolver = makeSimpleResolver()

    let cell = resolver.cell(at: CGPoint(x: 9999, y: 150))
    #expect(cell?.col == 2)
    #expect(cell?.row == 0)
}

@Test func cursorBeyondBottomEdgeClampsToLastRow() {
    let resolver = makeSimpleResolver()

    let cell = resolver.cell(at: CGPoint(x: 150, y: 9999))
    #expect(cell?.row == 2)
    #expect(cell?.col == 0)
}

@Test func cursorToLeftOfGridClampsToFirstColumn() {
    let resolver = makeSimpleResolver()

    let cell = resolver.cell(at: CGPoint(x: -100, y: 450))
    #expect(cell?.col == 0)
}

@Test func cursorAboveGridClampsToFirstRow() {
    let resolver = makeSimpleResolver()

    let cell = resolver.cell(at: CGPoint(x: 450, y: -100))
    #expect(cell?.row == 0)
}

@Test func multiCellRegionUnionSingleCell() {
    let resolver = makeSimpleResolver()
    let from = GridCell(row: 1, col: 1)
    let to   = GridCell(row: 1, col: 1)

    let rect = resolver.region(from: from, to: to)
    #expect(rect != nil)
    // Should equal cell [1][1]: (300,300,300,300)
    #expect(abs((rect?.origin.x ?? 0) - 300) < 0.001)
    #expect(abs((rect?.origin.y ?? 0) - 300) < 0.001)
    #expect(abs((rect?.width  ?? 0) - 300) < 0.001)
    #expect(abs((rect?.height ?? 0) - 300) < 0.001)
}

@Test func multiCellRegionUnionTwoByTwo() {
    let resolver = makeSimpleResolver()
    // Cells [0][0] through [1][1] → union (0,0) to (600,600)
    let rect = resolver.region(from: GridCell(row: 0, col: 0),
                               to:   GridCell(row: 1, col: 1))
    #expect(rect != nil)
    #expect(abs((rect?.origin.x ?? 1) - 0)   < 0.001)
    #expect(abs((rect?.origin.y ?? 1) - 0)   < 0.001)
    #expect(abs((rect?.width  ?? 0) - 600) < 0.001)
    #expect(abs((rect?.height ?? 0) - 600) < 0.001)
}

@Test func multiCellRegionOrderIndependent() {
    let resolver = makeSimpleResolver()
    let a = resolver.region(from: GridCell(row: 0, col: 0), to: GridCell(row: 2, col: 2))
    let b = resolver.region(from: GridCell(row: 2, col: 2), to: GridCell(row: 0, col: 0))
    #expect(a == b)
}

@Test func multiCellRegionFullGrid() {
    let resolver = makeSimpleResolver()
    let rect = resolver.region(from: GridCell(row: 0, col: 0),
                               to:   GridCell(row: 2, col: 2))
    #expect(abs((rect?.width  ?? 0) - 900) < 0.001)
    #expect(abs((rect?.height ?? 0) - 900) < 0.001)
}

@Test func cursorBasedRegion() {
    let resolver = makeSimpleResolver()
    // Start in cell [0][0], end in cell [1][1]
    let rect = resolver.region(from: CGPoint(x: 150, y: 150),
                               to:   CGPoint(x: 450, y: 450))
    #expect(rect != nil)
    #expect(abs((rect?.width  ?? 0) - 600) < 0.001)
    #expect(abs((rect?.height ?? 0) - 600) < 0.001)
}
