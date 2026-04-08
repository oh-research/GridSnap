@preconcurrency import Cocoa

/// An NSView that draws the grid lines and highlights selected cells.
/// All AppKit access must happen on the main thread.
@MainActor
final class GridOverlayView: NSView {

    // MARK: - Public state

    /// 2D array of cell CGRects in the view's own coordinate system (flipped, top-left origin).
    var gridCells: [[CGRect]] = [] {
        didSet { needsDisplay = true }
    }

    /// Cells that should be drawn with a highlight fill.
    var highlightedCells: Set<GridCell> = [] {
        didSet {
            guard highlightedCells != oldValue else { return }
            needsDisplay = true
        }
    }

    // MARK: - Style constants (dynamic, updated on appearance change)

    private var gridLineColor: NSColor = NSColor.white.withAlphaComponent(0.15)
    private let gridLineWidth: CGFloat = 0.5

    private var highlightFill: NSColor = NSColor.systemBlue.withAlphaComponent(0.30)
    private var highlightStroke: NSColor = NSColor.systemBlue.withAlphaComponent(0.85)
    private let highlightLineWidth: CGFloat = 2.0

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        updateColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = .clear
        updateColors()
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        needsDisplay = true
    }

    private func updateColors() {
        let isDark = effectiveAppearance.name == .darkAqua
            || effectiveAppearance.name == .vibrantDark
            || effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDark {
            gridLineColor  = NSColor.white.withAlphaComponent(0.15)
        } else {
            gridLineColor  = NSColor.darkGray.withAlphaComponent(0.20)
        }
        // Highlight colors are the same for both modes (system blue)
        highlightFill   = NSColor.systemBlue.withAlphaComponent(0.30)
        highlightStroke = NSColor.systemBlue.withAlphaComponent(0.85)
    }

    // MARK: - Drawing

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !gridCells.isEmpty else { return }

        NSGraphicsContext.current?.shouldAntialias = true

        drawGridLines()
        drawHighlightedCells()
    }

    private func drawGridLines() {
        gridLineColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = gridLineWidth

        for row in gridCells {
            for cellRect in row {
                path.appendRect(cellRect)
            }
        }
        path.stroke()
    }

    private func drawHighlightedCells() {
        guard !highlightedCells.isEmpty else { return }

        // Compute the bounding union of all highlighted cells so we can draw a single
        // continuous highlight for rectangular multi-cell selections.
        var union: CGRect?
        for cell in highlightedCells {
            guard cell.row < gridCells.count,
                  cell.col < gridCells[cell.row].count else { continue }
            let rect = gridCells[cell.row][cell.col]
            union = union.map { $0.union(rect) } ?? rect
        }

        guard let highlightRect = union else { return }

        highlightFill.setFill()
        let fillPath = NSBezierPath(rect: highlightRect)
        fillPath.fill()

        highlightStroke.setStroke()
        let strokePath = NSBezierPath(rect: highlightRect.insetBy(dx: highlightLineWidth / 2,
                                                                   dy: highlightLineWidth / 2))
        strokePath.lineWidth = highlightLineWidth
        strokePath.stroke()
    }
}
