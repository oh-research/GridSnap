import Cocoa

/// Creates the GridSnap menu bar icon as a template `NSImage`.
///
/// The design is a 3x3 grid inside a rounded rectangle border — the visual
/// shorthand for "snap to grid". The image is marked `isTemplate = true`, so
/// AppKit automatically tints it for dark/light menu bars and highlight
/// states — never color it manually.
///
/// Tune the visual weight via the three constants in `draw(in:)`:
/// `inset`, `lineWidth`, `cornerRadius`.
enum MenuBarIcon {

    /// Returns a new template image. `size` defaults to `18`, which matches
    /// the standard `NSStatusItem.squareLength` on macOS.
    static func make(size: CGFloat = 18) -> NSImage {
        let nsSize = NSSize(width: size, height: size)
        let image = NSImage(size: nsSize, flipped: true) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Drawing

    /// Proportional drawing so the shape scales cleanly at any size.
    /// All metrics are expressed relative to an 18pt base canvas and
    /// multiplied by the actual `rect.width`.
    private static func draw(in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let scale = rect.width / 18.0
        let inset = 1.0 * scale
        let lineWidth = 1.0 * scale
        let cornerRadius = 2.0 * scale

        let gridRect = rect.insetBy(dx: inset, dy: inset)
        let cellW = gridRect.width / 3
        let cellH = gridRect.height / 3

        ctx.setLineWidth(lineWidth)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineCap(.square)

        // 1. Outer rounded border. Inset by half the line width so the stroke
        //    stays inside `gridRect` (avoids aliasing at the canvas edge).
        let borderInset = lineWidth / 2
        let borderPath = CGPath(
            roundedRect: gridRect.insetBy(dx: borderInset, dy: borderInset),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(borderPath)
        ctx.strokePath()

        // 2. Inner 3x3 grid lines (2 vertical + 2 horizontal).
        for i in 1..<3 {
            let x = gridRect.minX + cellW * CGFloat(i)
            let y = gridRect.minY + cellH * CGFloat(i)
            ctx.move(to: CGPoint(x: x, y: gridRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: gridRect.maxY))
            ctx.move(to: CGPoint(x: gridRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        ctx.strokePath()
    }
}

