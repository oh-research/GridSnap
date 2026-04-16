@preconcurrency import Cocoa

// MARK: - WindowManipulator

/// Moves and resizes windows by writing AX attributes.
/// All methods are safe to call from any thread.
final class WindowManipulator: Sendable {

    static let shared = WindowManipulator()

    // MARK: - Public API

    /// Moves and resizes `element` to `frame` (CG coordinate system).
    /// Returns true on success.
    ///
    /// Order: size → position → size. The first size lets the window
    /// shrink to fit (respecting any minimum-size constraint) before
    /// the move, preventing the window from overflowing the target
    /// cell while still at its original dimensions. Position then
    /// moves the (possibly-resized) window. The final size re-applies
    /// because several apps — observed in the wild on cross-monitor
    /// snaps — reset their size back to the pre-move value during the
    /// position change. Costs one extra AX round-trip (5–15 ms on
    /// slow apps) but is worth it for a crisp, single-step snap.
    ///
    /// No pre-validation: a closed / invalid element fails the AX
    /// writes synchronously and returns `false`, avoiding an extra
    /// AX round-trip on every snap.
    @discardableResult
    func setFrame(_ frame: CGRect, for element: AXUIElement) -> Bool {
        _ = writeSize(frame.size, for: element)
        let posOK = writePosition(frame.origin, for: element)
        let sizeOK = writeSize(frame.size, for: element)
        return posOK && sizeOK
    }

    /// Moves `element` to `position` (CG coordinate system).
    @discardableResult
    func setPosition(_ position: CGPoint, for element: AXUIElement) -> Bool {
        guard isValid(element) else { return false }
        return writePosition(position, for: element)
    }

    /// Resizes `element` to `size`.
    @discardableResult
    func setSize(_ size: CGSize, for element: AXUIElement) -> Bool {
        guard isValid(element) else { return false }
        return writeSize(size, for: element)
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

    /// Writes a position without re-validating the element. Used by
    /// `setFrame`, which already validated once at entry.
    private func writePosition(_ position: CGPoint, for element: AXUIElement) -> Bool {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    /// Writes a size without re-validating the element.
    private func writeSize(_ size: CGSize, for element: AXUIElement) -> Bool {
        var sz = size
        guard let value = AXValueCreate(.cgSize, &sz) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }
}
