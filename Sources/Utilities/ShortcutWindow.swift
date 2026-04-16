import AppKit

/// NSWindow subclass that handles the two standard macOS window
/// shortcuts — Cmd+W (close) and Cmd+Q (quit app) — without requiring
/// the app to install a main menu.
///
/// Menu-bar-only apps like sniq normally ignore Cmd+W/Cmd+Q because
/// macOS wires those shortcuts through `NSApp.mainMenu`. Since we don't
/// install a main menu (to avoid showing an app menu next to the status
/// bar icon), the two shortcuts become inert inside our Settings/About/
/// Onboarding windows. Overriding `performKeyEquivalent` restores the
/// standard behavior scoped to these windows only.
final class ShortcutWindow: NSWindow {

    // Physical-key codes from Carbon's `Events.h` (`kVK_ANSI_*`). We match
    // on keyCode instead of `charactersIgnoringModifiers` because the
    // latter returns IME-composed characters (e.g. Hangul `ᆯ` instead of
    // `w` under a Korean input source), which silently breaks the switch.
    private static let keyCodeW: UInt16 = 13
    private static let keyCodeQ: UInt16 = 12

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommandShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleCommandShortcut(event) { return }
        super.keyDown(with: event)
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        else { return false }
        switch event.keyCode {
        case Self.keyCodeW:
            performClose(nil)
            return true
        case Self.keyCodeQ:
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }
}
