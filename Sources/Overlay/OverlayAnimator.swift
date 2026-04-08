@preconcurrency import Cocoa

/// Drives fade-in, fade-out, success-flash, and cancel animations for an overlay window.
/// All methods must be called on the main thread.
@MainActor
final class OverlayAnimator {

    // MARK: - Constants

    private let fadeInDuration:      TimeInterval = 0.2
    private let fadeOutDuration:     TimeInterval = 0.3
    private let flashBrightDuration: TimeInterval = 0.1
    private let flashFadeDuration:   TimeInterval = 0.25

    // MARK: - Public interface

    /// Fades the window in from transparent to fully opaque.
    func fadeIn(window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 1
        }
    }

    /// Fades the window out, then hides it when the animation completes.
    func fadeOut(window: NSWindow) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                window.orderOut(nil)
                window.alphaValue = 1   // reset for next show
            }
        })
    }

    /// Briefly brightens the overlay highlight, then fades the window out.
    /// Useful for communicating a successful snap.
    func successFlash(window: NSWindow, overlayView: GridOverlayView) {
        // Phase 1: ensure window is fully visible.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = flashBrightDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 1
        }, completionHandler: {
            // Phase 2: fade out completely.
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = self.flashFadeDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        window.orderOut(nil)
                        window.alphaValue = 1
                        overlayView.highlightedCells = []
                    }
                })
            }
        })
    }

    /// Immediately hides the window without any animation.
    func cancelHide(window: NSWindow, overlayView: GridOverlayView) {
        window.alphaValue = 1
        window.orderOut(nil)
        overlayView.highlightedCells = []
    }
}
