@preconcurrency import Cocoa
import ApplicationServices

/// Caches the AX element of the currently focused window so that each
/// keyboard snap avoids two system-wide AX round-trips
/// (`focusedApplication` + `focusedWindow`).
///
/// Invalidation triggers:
/// - `NSWorkspace.didActivateApplicationNotification` — app switch
/// - `NSWorkspace.didTerminateApplicationNotification` — app crash/quit
/// - `kAXFocusedWindowChangedNotification` on the frontmost app —
///   same-app window focus change (e.g. user clicks a window on
///   another monitor, Cmd+backtick, etc.)
final class FocusedWindowCache: @unchecked Sendable {

    static let shared = FocusedWindowCache()

    private let lock = NSLock()
    private var cached: AXUIElement?
    /// AXObserver for the current frontmost app — fires when the user
    /// switches focus between that app's windows (e.g. across monitors).
    /// Replaced on every NSWorkspace activation so we always track the
    /// frontmost app's focus events.
    private var axObserver: AXObserver?
    /// Incremented on every `invalidate()`. A background `refresh()` captures
    /// the generation before its AX query and only installs its result if
    /// the generation is still current — prevents a slow refresh from a
    /// stale app from overwriting an invalidated slot after the user has
    /// already switched apps.
    private var generation: UInt = 0
    /// Non-empty iff the NSWorkspace observers are currently registered.
    /// The tokens must stay alive for the lifetime of the observers;
    /// `stop()` is the only path that should clear them.
    private var observerTokens: [NSObjectProtocol] = []
    private let refreshQueue = DispatchQueue(
        label: "com.sniq.focusedwindowcache",
        qos: .userInitiated
    )

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard observerTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        // Invalidate on both app activation (focus changed) and app
        // termination (crashed app's cached element now references a
        // dead process — first subsequent snap would otherwise silently
        // no-op).
        let triggers: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        observerTokens = triggers.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.invalidate()
                self?.refresh()
                self?.attachAXObserverForFrontmost()
            }
        }
        // Warm the cache immediately and start observing the frontmost
        // app so the very first keypress after launch doesn't pay a
        // synchronous AX round-trip on the tap thread.
        refresh()
        attachAXObserverForFrontmost()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in observerTokens { center.removeObserver(token) }
        observerTokens.removeAll()
        detachAXObserver()
        invalidate()
    }

    // MARK: - AX focused-window observer

    /// Replaces `axObserver` with one attached to the current frontmost
    /// app. Fires on same-app window focus changes, which NSWorkspace
    /// does not expose. Must run on the main thread because it mutates
    /// the main run loop.
    private func attachAXObserverForFrontmost() {
        detachAXObserver()
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontmost.processIdentifier

        var observer: AXObserver?
        let status = AXObserverCreate(pid, Self.axCallback, &observer)
        guard status == .success, let observer else { return }

        let app = AXUIElementCreateApplication(pid)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            observer, app, kAXFocusedWindowChangedNotification as CFString, selfPtr
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
        )
        axObserver = observer
    }

    private func detachAXObserver() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
        )
        axObserver = nil
    }

    /// C-compatible callback trampoline — invalidates + refreshes the
    /// cache when the observed app's focused window changes.
    private static let axCallback: AXObserverCallback = { _, _, _, userInfo in
        guard let userInfo else { return }
        let cache = Unmanaged<FocusedWindowCache>.fromOpaque(userInfo).takeUnretainedValue()
        cache.invalidate()
        cache.refresh()
    }

    // MARK: - Background refresh

    /// Asynchronously repopulates the cache on a background queue so
    /// the tap callback thread never blocks on a fresh AX query for
    /// the common post-activation case. Called on `start()` and
    /// whenever the frontmost application changes or terminates.
    ///
    /// Uses the generation counter to avoid a race where a slow AX
    /// query from a prior app finishes after the user has already
    /// switched away, installing a stale window.
    private func refresh() {
        lock.lock()
        let capturedGeneration = generation
        lock.unlock()

        refreshQueue.async { [weak self] in
            guard let self else { return }
            guard let window = FocusedWindowDetector.focusedWindow() else { return }
            self.lock.lock()
            if self.generation == capturedGeneration {
                self.cached = window
            }
            self.lock.unlock()
        }
    }

    // MARK: - Access

    /// Returns the current focused window, from cache or via a fresh
    /// AX query. Safe to call from any thread. Returns `nil` only when
    /// no window is actually focused (desktop, app without windows,
    /// permission denied).
    var focusedWindow: AXUIElement? {
        lock.lock()
        if let hit = cached {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let window = FocusedWindowDetector.focusedWindow() else { return nil }

        lock.lock()
        // If another thread raced ahead and populated the cache while we
        // were querying, prefer its entry so we don't clobber a value
        // that may already be more recent than ours.
        let result = cached ?? window
        cached = result
        lock.unlock()
        return result
    }

    /// Forces the next `focusedWindow` read to fetch fresh from AX.
    /// Call when a cached window is suspected stale (e.g. `frame(of:)`
    /// returned nil, window was closed mid-session).
    func invalidate() {
        lock.lock()
        cached = nil
        generation &+= 1
        lock.unlock()
    }
}
