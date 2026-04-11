@preconcurrency import Cocoa
import ApplicationServices

/// Queries the accessibility tree for the currently focused window of the
/// frontmost application and detects whether the focused UI element is a
/// text-editing target. Used by `KeyboardSnapCoordinator` to decide whether
/// to intercept a Sniq keyboard shortcut or let macOS deliver it to the
/// text field for native selection.
enum FocusedWindowDetector {

    /// Returns the focused window of the frontmost application, or `nil`
    /// if no window is available (Finder desktop focus, permission denied,
    /// Electron apps that don't expose AX properly, etc.).
    static func focusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)

        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard appResult == .success, let app = focusedApp else { return nil }

        var focusedWindow: CFTypeRef?
        let winResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard winResult == .success, let window = focusedWindow else { return nil }
        return (window as! AXUIElement)
    }

    /// Reads the frame (position + size) of the given AX window element in
    /// CG coordinates (top-left origin). Returns `nil` if either attribute
    /// is missing or malformed.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef
        else { return nil }

        var cgPosition = CGPoint.zero
        var cgSize = CGSize.zero
        let pos = positionValue as! AXValue
        let siz = sizeValue as! AXValue
        guard AXValueGetType(pos) == .cgPoint,
              AXValueGetValue(pos, .cgPoint, &cgPosition),
              AXValueGetType(siz) == .cgSize,
              AXValueGetValue(siz, .cgSize, &cgSize)
        else { return nil }

        return CGRect(origin: cgPosition, size: cgSize)
    }

    /// Returns the NSScreen whose visible frame contains the center of
    /// `frame` (CG coordinates). Falls back to `NSScreen.main` if no
    /// screen contains the point.
    @MainActor
    static func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for screen in NSScreen.screens where screen.visibleFrameCG.contains(center) {
            return screen
        }
        return NSScreen.main
    }

    /// True when the frontmost focused UI element accepts text input.
    /// Called synchronously from the CGEventTap callback; uses a 100ms
    /// AX messaging timeout to avoid blocking the tap budget on unresponsive
    /// (Electron, etc.) apps. On timeout or unknown role, returns `false`
    /// (i.e. Sniq will handle the shortcut). The user can disable the whole
    /// feature from Settings if this heuristic misbehaves on their apps.
    ///
    /// Terminal emulators are bypassed: they expose their terminal view as
    /// `AXTextArea` but users typically want window snapping to win there
    /// (Shift+Opt+Arrow in a terminal emits escape sequences rather than
    /// performing native word selection).
    static func isTextElementFocused() -> Bool {
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           terminalBundleIDs.contains(bundleID) {
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let element = focusedElement else { return false }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success, let role = roleRef as? String
        else { return false }

        switch role {
        case kAXTextFieldRole as String,
             kAXTextAreaRole as String,
             kAXComboBoxRole as String:
            return true
        default:
            return false
        }
    }

    /// Bundle identifiers of terminal emulators where text pass-through is
    /// intentionally skipped. Add more here if a terminal app reports as
    /// a text area and blocks keyboard snap.
    private static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty"
    ]
}
