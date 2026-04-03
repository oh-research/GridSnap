@preconcurrency import Cocoa
import Combine

@MainActor
final class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    @Published private(set) var isTrusted: Bool = false
    @Published private(set) var canListenEvents: Bool = false

    // MARK: - Permission polling

    private var pollingTimer: Timer?

    var allPermissionsGranted: Bool {
        isTrusted && canListenEvents
    }

    func checkPermission() {
        isTrusted = AXIsProcessTrusted()
        canListenEvents = checkInputMonitoring()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings to the Input Monitoring pane.
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Checks if Input Monitoring is available by attempting a temporary CGEventTap.
    private func checkInputMonitoring() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        // Tap created successfully — clean up immediately
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    /// Begins polling every `interval` seconds, publishing changes.
    /// Stops automatically once all permissions are granted.
    func startPolling(interval: TimeInterval = 2.0) {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let trusted = AXIsProcessTrusted()
                let listen = self.checkInputMonitoring()
                if trusted != self.isTrusted { self.isTrusted = trusted }
                if listen != self.canListenEvents { self.canListenEvents = listen }
                if trusted && listen {
                    self.stopPolling()
                }
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - AXError helpers

    /// Returns true when an AXError indicates that AX permission has been
    /// revoked system-wide (kAXErrorAPIDisabled).
    static func isPermissionLoss(_ error: AXError) -> Bool {
        error == .apiDisabled
    }

    /// Returns true when an AXError indicates the UI element is no longer valid
    /// (window closed, app quit, etc.).
    static func isInvalidElement(_ error: AXError) -> Bool {
        error == .invalidUIElement || error == .invalidUIElementObserver
    }

    /// Classifies an AXError into a user-facing category.
    static func classify(_ error: AXError) -> AXErrorCategory {
        if isPermissionLoss(error)  { return .permissionLost }
        if isInvalidElement(error)  { return .elementInvalid }
        if error == .success        { return .none }
        return .other(error)
    }
}

// MARK: - AXErrorCategory

enum AXErrorCategory: Sendable {
    case none
    case permissionLost
    case elementInvalid
    case other(AXError)
}
