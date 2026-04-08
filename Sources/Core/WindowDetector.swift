@preconcurrency import Cocoa

// MARK: - Private API binding

private typealias AXUIElementGetWindowFn =
    @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private let _axGetWindowFn: AXUIElementGetWindowFn? = {
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(sym, to: AXUIElementGetWindowFn.self)
}()

// MARK: - WindowInfo

struct WindowInfo: @unchecked Sendable {
    let windowID: CGWindowID   // 0 if unknown
    let pid: pid_t
    let frame: CGRect          // CG coordinate system (top-left origin)
    let title: String
    let axElement: AXUIElement
    let isFullscreen: Bool

    /// True when the cursor Y is within `threshold` points of the window's top edge.
    ///
    /// The default of 80 covers title bar + toolbar for most apps (Finder, Safari,
    /// Notes, etc.). macOS itself treats the toolbar area as draggable chrome, so
    /// GridSnap should honor user clicks in that region as drag-to-snap intent.
    func isTitleBar(cursorY: CGFloat, threshold: CGFloat = 80) -> Bool {
        let distFromTop = cursorY - frame.minY
        return distFromTop >= 0 && distFromTop <= threshold
    }
}


// MARK: - WindowDetector

/// Detects the window under a given screen-space point using:
///   1. AXUIElementCopyElementAtPosition  (primary)
///   2. CGWindowListCopyWindowInfo        (fallback)
///
/// All methods are safe to call off the main thread.
final class WindowDetector: Sendable {

    static let shared = WindowDetector()

    // MARK: - Public API

    /// Returns the window at `point` (CG coordinate system).
    /// Returns nil if no window found or AX permission is unavailable.
    func windowAtPoint(_ point: CGPoint) -> WindowInfo? {
        // Primary: AX tree walk
        if let info = windowViaAX(at: point) {
            return info
        }
        // Fallback: CGWindowList
        return windowViaCGWindowList(at: point)
    }

    // MARK: - AX primary path

    private func windowViaAX(at point: CGPoint) -> WindowInfo? {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &elementRef
        )
        guard result == .success, let element = elementRef else { return nil }

        guard let windowElement = walkToWindow(from: element) else { return nil }

        return buildWindowInfo(from: windowElement, cursorPoint: point)
    }

    /// Walk the AX parent chain until we reach an AXWindow role (max 10 steps).
    private func walkToWindow(from element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<10 {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String, role == (kAXWindowRole as String) {
                return current
            }
            var parentRef: CFTypeRef?
            let pr = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef)
            guard pr == .success, let parent = parentRef else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func buildWindowInfo(from windowElement: AXUIElement, cursorPoint: CGPoint) -> WindowInfo? {
        // Position
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        guard size.width > 0 && size.height > 0 else { return nil }

        // Title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        // PID
        var pid: pid_t = 0
        AXUIElementGetPid(windowElement, &pid)

        // CGWindowID via private API
        let windowID = cgWindowID(from: windowElement)

        let frame = CGRect(origin: pos, size: size)

        // Check fullscreen via AX attribute, then fallback to frame == screen frame
        let isFullscreen = checkFullscreen(element: windowElement, frame: frame)

        return WindowInfo(
            windowID: windowID,
            pid: pid,
            frame: frame,
            title: title,
            axElement: windowElement,
            isFullscreen: isFullscreen
        )
    }

    private func checkFullscreen(element: AXUIElement, frame: CGRect) -> Bool {
        // Primary: AXFullScreen attribute (string literal; kAXFullScreenAttribute is unavailable in Swift)
        var fsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &fsRef)
        if let fsVal = fsRef as? Bool {
            return fsVal
        }
        // Fallback: window frame equals a screen frame
        for screen in NSScreen.screens {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let screenCGFrame = CGRect(
                x: screen.frame.origin.x,
                y: primaryHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height
            )
            if frame == screenCGFrame {
                return true
            }
        }
        return false
    }

    // MARK: - CGWindowList fallback

    private func windowViaCGWindowList(at point: CGPoint) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in list {
            guard
                let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let w = bounds["Width"], let h = bounds["Height"]
            else { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            guard rect.contains(point) else { continue }

            let windowID = (window[kCGWindowNumber as String] as? Int).map { CGWindowID($0) } ?? 0
            let ownerPID = (window[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } ?? 0
            let title = (window[kCGWindowName as String] as? String) ?? ""

            // Find the actual AX window element matching this CGWindowID
            let appElement = AXUIElementCreateApplication(ownerPID)
            guard let windowElement = axWindow(from: appElement, matching: windowID) else { continue }

            let isFullscreen = checkFullscreen(element: windowElement, frame: rect)

            return WindowInfo(
                windowID: windowID,
                pid: ownerPID,
                frame: rect,
                title: title,
                axElement: windowElement,
                isFullscreen: isFullscreen
            )
        }
        return nil
    }

    // MARK: - AX window lookup by CGWindowID

    /// Finds the AX window element whose CGWindowID matches `targetID`.
    private func axWindow(from appElement: AXUIElement, matching targetID: CGWindowID) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows {
            let wid = cgWindowID(from: window)
            if wid == targetID {
                return window
            }
        }
        return nil
    }

    // MARK: - _AXUIElementGetWindow helper

    /// Returns the CGWindowID for an AX window element, or 0 if unavailable.
    func cgWindowID(from element: AXUIElement) -> CGWindowID {
        guard let fn = _axGetWindowFn else { return 0 }
        var wid: CGWindowID = 0
        let result = fn(element, &wid)
        return result == .success ? wid : 0
    }
}
