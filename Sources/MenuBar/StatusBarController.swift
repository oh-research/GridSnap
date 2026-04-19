import Cocoa
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var snapshotsWindow: NSWindow?

    /// When non-nil, the menu shows this as a disabled status line at
    /// the top and the status-bar icon switches to a warning glyph.
    private var errorMessage: String?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Error state

    func showError(_ message: String) {
        errorMessage = message
        updateIcon()
    }

    func clearError() {
        errorMessage = nil
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if errorMessage != nil {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Sniq Error"
            )?.withSymbolConfiguration(config)
        } else {
            button.image = MenuBarIcon.make()
        }
    }

    // MARK: - Actions (invoked by AppMenuBuilder via #selector)

    @objc func toggleEnabled(_ sender: NSMenuItem) {
        PreferencesStore.shared.isEnabled.toggle()
    }

    @objc func openSnapshots(_ sender: Any?) {
        showSnapshotsWindow()
    }

    @objc func openSettings(_ sender: Any?) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sniq Settings"
        let hosting = NSHostingView(rootView: SettingsView())
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        positionBelowStatusItem(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc func openOnboarding(_ sender: Any?) {
        showOnboarding()
    }

    @objc func openAbout(_ sender: Any?) {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Sniq"
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow = window
    }

    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "How to Use Sniq"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func showSnapshotsWindow() {
        if let existing = snapshotsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 860),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snapshots"
        window.contentView = NSHostingView(rootView: SnapshotsWindowView())
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        snapshotsWindow = window
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Window placement

    /// Places `window` just below the status-bar icon, right-aligned to
    /// it, so Settings opens next to the trigger instead of at screen
    /// center (minimizes cursor travel from the menu bar).
    private func positionBelowStatusItem(_ window: NSWindow) {
        guard let button = statusItem.button,
              let buttonWindow = button.window
        else {
            window.center()
            return
        }
        let buttonFrame = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let screenFrame = buttonWindow.screen?.visibleFrame ?? .zero
        let gap: CGFloat = 6
        let w = window.frame.width
        let h = window.frame.height
        let x = max(
            screenFrame.minX + 8,
            min(buttonFrame.maxX - w, screenFrame.maxX - w - 8)
        )
        let y = buttonFrame.minY - h - gap
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Menu delegate

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        AppMenuBuilder.rebuild(menu: menu, target: self, errorMessage: errorMessage)
    }
}

// MARK: - Window delegate

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window === snapshotsWindow {
            snapshotsWindow = nil
        }
        // Return to accessory policy (no Dock icon) once every auxiliary
        // window has closed.
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
