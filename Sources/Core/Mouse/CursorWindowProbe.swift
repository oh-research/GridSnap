@preconcurrency import Cocoa

/// Answers "is there an app window right under this screen point?"
/// without going through the Accessibility API. Uses
/// `CGWindowListCopyWindowInfo` restricted to layer 0 so desktop,
/// menubar, and Dock hits pass through to the OS. Isolated in its own
/// file so the GripDrag state machine stays focused on flow control.
enum CursorWindowProbe {

    static func hasWindow(at point: CGPoint) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for entry in list {
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let w = bounds["Width"], let h = bounds["Height"]
            else { continue }
            if CGRect(x: x, y: y, width: w, height: h).contains(point) {
                return true
            }
        }
        return false
    }
}
