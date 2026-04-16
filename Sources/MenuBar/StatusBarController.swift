import Cocoa
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?

    /// Non-interactive status menu item shown at top when an error is present.
    private var statusMenuItem: NSMenuItem?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
        }

        statusItem.menu = buildMenu()
    }

    // MARK: - Error state

    /// Shows an error indicator in the menu bar and adds a status item to the menu.
    func showError(_ message: String) {
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Sniq Error"
            )?.withSymbolConfiguration(config)
        }

        // Add or update the status menu item at the top
        if let existing = statusMenuItem {
            existing.title = message
        } else {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            statusMenuItem = item
            statusItem.menu?.insertItem(item, at: 0)
            statusItem.menu?.insertItem(.separator(), at: 1)
        }
    }

    /// Restores the normal menu bar icon and removes the error status item.
    func clearError() {
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
        }

        if let item = statusMenuItem, let menu = statusItem.menu {
            let idx = menu.index(of: item)
            if idx != -1 {
                // Also remove the separator that was inserted after it
                if idx + 1 < menu.items.count, menu.items[idx + 1].isSeparatorItem {
                    menu.removeItem(at: idx + 1)
                }
                menu.removeItem(at: idx)
            }
        }
        statusMenuItem = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = PreferencesStore.shared.isEnabled ? .on : .off
        menu.addItem(enableItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let howToItem = NSMenuItem(title: "How to Use...", action: #selector(openOnboarding(_:)), keyEquivalent: "")
        howToItem.target = self
        menu.addItem(howToItem)

        let aboutItem = NSMenuItem(title: "About Sniq", action: #selector(openAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Sniq", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        PreferencesStore.shared.isEnabled.toggle()
        sender.state = PreferencesStore.shared.isEnabled ? .on : .off
    }

    @objc private func openSettings(_ sender: Any?) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sniq Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        positionBelowStatusItem(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    /// Places `window` just below the status-bar icon, right-aligned to
    /// it, so Settings opens next to the trigger instead of at screen
    /// center (minimizes cursor travel from the menu bar). Falls back
    /// to `center()` when the status item's window is unavailable.
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
        // Align right edge of window with right edge of button.
        let x = max(
            screenFrame.minX + 8,
            min(buttonFrame.maxX - w, screenFrame.maxX - w - 8)
        )
        let y = buttonFrame.minY - h - gap
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func openOnboarding(_ sender: Any?) {
        showOnboarding()
    }

    @objc private func openAbout(_ sender: Any?) {
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

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When onboarding/settings window closes, go back to accessory (no Dock icon)
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
