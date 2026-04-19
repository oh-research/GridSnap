import Cocoa

/// Monochrome status-bar icon that mirrors the Sniq app-icon composition
/// — rounded 3×3 grid with a filled "window" tile in the top-left 2×2
/// region. Drawn as a template image so AppKit renders it in whichever
/// color the current menu bar uses (black on light, white on dark).
enum MenuBarIcon {

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

    private static func draw(in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let scale = rect.width / 18.0
        let borderWidth = 1.0 * scale
        let gridLineWidth = 0.6 * scale
        let cornerRadius = 3.0 * scale
        let inset = 1.0 * scale

        let gridRect = rect.insetBy(dx: inset, dy: inset)
        let cellW = gridRect.width / 3
        let cellH = gridRect.height / 3

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setLineCap(.round)

        // 1. Outer rounded border — the "screen" of the icon.
        let borderInset = borderWidth / 2
        let borderPath = CGPath(
            roundedRect: gridRect.insetBy(dx: borderInset, dy: borderInset),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.setLineWidth(borderWidth)
        ctx.addPath(borderPath)
        ctx.strokePath()

        // 2. Faint 3×3 grid lines inside the border (dimmer than the
        //    border and the filled window so the window reads as the
        //    primary subject).
        ctx.saveGState()
        ctx.setAlpha(0.35)
        ctx.setLineWidth(gridLineWidth)
        for i in 1..<3 {
            let x = gridRect.minX + cellW * CGFloat(i)
            let y = gridRect.minY + cellH * CGFloat(i)
            ctx.move(to: CGPoint(x: x, y: gridRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: gridRect.maxY))
            ctx.move(to: CGPoint(x: gridRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Filled window in the top-left 2×2 — the app's signature
        //    "window snapped to a region" motif.
        let windowInset = 1.4 * scale
        let windowRect = CGRect(
            x: gridRect.minX + windowInset,
            y: gridRect.minY + windowInset,
            width: cellW * 2 - windowInset * 2,
            height: cellH * 2 - windowInset * 2
        )
        let windowPath = CGPath(
            roundedRect: windowRect,
            cornerWidth: 1.2 * scale,
            cornerHeight: 1.2 * scale,
            transform: nil
        )
        ctx.addPath(windowPath)
        ctx.fillPath()
    }
}
