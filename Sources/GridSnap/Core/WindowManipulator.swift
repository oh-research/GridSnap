@preconcurrency import Cocoa

// MARK: - WindowManipulator

/// Moves and resizes windows by writing AX attributes.
/// All methods are safe to call from any thread.
final class WindowManipulator: Sendable {

    static let shared = WindowManipulator()

    // MARK: - Public API

    /// Moves and resizes `element` to `frame` (CG coordinate system).
    /// Returns true on success.
    @discardableResult
    func setFrame(_ frame: CGRect, for element: AXUIElement) -> Bool {
        guard isValid(element) else { return false }
        let posOK = setPosition(frame.origin, for: element)
        let sizeOK = setSize(frame.size, for: element)
        return posOK && sizeOK
    }

    /// Moves `element` to `position` (CG coordinate system).
    @discardableResult
    func setPosition(_ position: CGPoint, for element: AXUIElement) -> Bool {
        guard isValid(element) else { return false }
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return retry {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
        }
    }

    /// Resizes `element` to `size`.
    @discardableResult
    func setSize(_ size: CGSize, for element: AXUIElement) -> Bool {
        guard isValid(element) else { return false }
        var sz = size
        guard let value = AXValueCreate(.cgSize, &sz) else { return false }
        return retry {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
        }
    }

    // MARK: - Validation

    /// Returns false if the AX element is no longer usable (e.g. window was closed).
    func isValid(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        // kAXErrorInvalidUIElement or kAXErrorAPIDisabled indicate the element is gone.
        return result != .invalidUIElement && result != .apiDisabled
    }

    // MARK: - Private helpers

    /// Retries `body` up to 3 times with a short delay between attempts.
    private func retry(attempts: Int = 3, delayNs: UInt64 = 15_000_000, body: () -> Bool) -> Bool {
        for attempt in 0..<attempts {
            if body() { return true }
            if attempt < attempts - 1 {
                // ~15 ms pause before next attempt
                Thread.sleep(forTimeInterval: Double(delayNs) / 1_000_000_000)
            }
        }
        return false
    }
}
