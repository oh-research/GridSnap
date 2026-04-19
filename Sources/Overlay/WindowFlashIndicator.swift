@preconcurrency import Cocoa

/// Briefly outlines the window that was grabbed at the start of a Grip
/// drag, so users get a "you got it" cue without the window itself
/// moving. Borderless transparent NSWindow that fades out after
/// `flashDuration` and orderOut's. The single window instance is
/// reused across drags; rapid re-flashes are guarded by `flashID` so
/// a stale completion handler never hides a fresh flash.
@MainActor
final class WindowFlashIndicator {

    private static let flashDuration: TimeInterval = 0.15
    private static let strokeWidth: CGFloat = 2.0

    private var window: NSWindow?
    private var view: FlashOutlineView?
    private var flashID: UInt64 = 0

    func flash(cgFrame: CGRect) {
        guard let cocoaRect = Self.cocoaRect(from: cgFrame) else { return }

        flashID &+= 1
        let myID = flashID

        let window = ensureWindow()
        window.setFrame(cocoaRect, display: false)
        view?.frame = NSRect(origin: .zero, size: cocoaRect.size)
        view?.needsDisplay = true

        window.alphaValue = 1.0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.flashDuration
            context.allowsImplicitAnimation = false
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            // NSAnimationContext invokes the completion on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.flashID == myID else { return }
                self.window?.orderOut(nil)
            }
        })
    }

    private func ensureWindow() -> NSWindow {
        if let existing = window { return existing }
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .none

        let view = FlashOutlineView(frame: .zero)
        window.contentView = view
        self.window = window
        self.view = view
        return window
    }

    private static func cocoaRect(from cgFrame: CGRect) -> NSRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return NSRect(
            x: cgFrame.origin.x,
            y: primaryHeight - cgFrame.origin.y - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }
}

@MainActor
private final class FlashOutlineView: NSView {

    private static let strokeWidth: CGFloat = 2.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.actions = [:]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.actions = [:]
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = Self.strokeWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = Self.strokeWidth
        path.stroke()
    }
}
