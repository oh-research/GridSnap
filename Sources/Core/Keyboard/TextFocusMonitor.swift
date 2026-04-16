@preconcurrency import Cocoa
import ApplicationServices
import os

/// Caches whether the currently focused UI element accepts text input.
///
/// The keyboard snap coordinator needs this answer synchronously on the
/// CGEventTap callback thread. Doing the underlying AX query on every
/// keystroke blocks the tap for up to 100 ms on a cold cache or an
/// unresponsive app — which manifests as the very first Shift+Opt+Arrow
/// being dropped, or intermittent misses during rapid key repeat.
///
/// Strategy: compute the value asynchronously on a background queue
/// whenever the frontmost application changes, store it behind an
/// unfair lock, and let the tap callback read the cached bool in <1 µs.
final class TextFocusMonitor: @unchecked Sendable {

    static let shared = TextFocusMonitor()

    private let state = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let refreshQueue = DispatchQueue(
        label: "com.sniq.textfocusmonitor",
        qos: .userInitiated
    )
    private var observer: NSObjectProtocol?

    private init() {}

    /// Whether the currently focused UI element is a text field, text area,
    /// or combo box. Safe to call from any thread.
    var isTextFocused: Bool {
        state.withLock { $0 }
    }

    // MARK: - Lifecycle

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        // Warm the cache and the AX XPC channel immediately so the first
        // keypress doesn't pay the cold-start cost.
        refresh()
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    // MARK: - Refresh

    private func refresh() {
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let value = Self.computeIsTextFocused()
            self.state.withLock { $0 = value }
        }
    }

    /// The expensive AX query, isolated to a background queue. Returns
    /// `false` on any failure (timeout, unknown role, missing element) so
    /// that sniq claims the shortcut — the safer default when we cannot
    /// prove text focus.
    private static func computeIsTextFocused() -> Bool {
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
    /// intentionally skipped. Terminals expose their view as `AXTextArea`
    /// but users want window snapping to win there (Shift+Opt+Arrow in a
    /// terminal emits escape sequences rather than selecting words).
    private static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty"
    ]
}
