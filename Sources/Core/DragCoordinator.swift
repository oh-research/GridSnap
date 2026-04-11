@preconcurrency import Cocoa
import Combine

/// Connects EventMonitor, DragStateMachine, WindowDetector, WindowManipulator,
/// GridCalculator, SnapResolver, and OverlayWindowController into a working
/// drag-to-snap pipeline.
///
/// Lifecycle: created once by AppDelegate, started/stopped via `start()` / `stop()`.
@MainActor
final class DragCoordinator {

    // MARK: - Dependencies

    private let eventMonitor = EventMonitor()
    private let stateMachine = DragStateMachine()
    private let windowDetector = WindowDetector.shared
    private let windowManipulator = WindowManipulator.shared
    private let overlayAnimator = OverlayAnimator()

    /// Injected by AppDelegate so error states can be shown in the menu bar.
    weak var statusBarController: StatusBarController?

    // Per-screen overlay controllers keyed by displayID
    private var overlayControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    // The controller currently showing (if any)
    private var activeOverlayController: OverlayWindowController?

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var resolver: SnapResolver?
    private var gridCells: [[CGRect]] = []
    private var isOverlayVisible = false

    /// Thread-safe storage for data shared between the event queue and main actor.
    private let shared = SharedState()

    // MARK: - Lifecycle

    func start() {
        setupStateMachineHooks()
        observeStateChanges()
        observePreferences()
        observeScreenChanges()
        observeAccessibility()
        eventMonitor.delegate = self
        KeyboardSnapCoordinator.shared.wire(to: eventMonitor)
        eventMonitor.onTapCreationFailure = { [weak self] in
            Task { @MainActor [weak self] in
                self?.statusBarController?.showError("Could not create event tap. Check Accessibility permission.")
            }
        }
        eventMonitor.start()
    }

    func stop() {
        eventMonitor.stop()
        cancellables.removeAll()
        hideOverlay()
    }

    // MARK: - Preferences observation

    private func observePreferences() {
        shared.isEnabled = PreferencesStore.shared.isEnabled

        PreferencesStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let enabled = PreferencesStore.shared.isEnabled
                self.shared.isEnabled = enabled
                if !enabled {
                    self.stateMachine.process(.cancel)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Accessibility observation

    private func observeAccessibility() {
        AccessibilityManager.shared.$isTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    self.statusBarController?.clearError()
                } else {
                    self.statusBarController?.showError("Accessibility permission required for window snapping.")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen change observation

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
        }
    }

    private func handleScreenChange() {
        // Remove overlay controllers for screens that no longer exist
        let currentIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        let removedIDs = Set(overlayControllers.keys).subtracting(currentIDs)
        for id in removedIDs {
            overlayControllers[id]?.hide()
            overlayControllers.removeValue(forKey: id)
        }
        if let activeScreen = activeScreen, !currentIDs.contains(activeScreen.displayID ?? 0) {
            activeOverlayController = nil
            isOverlayVisible = false
        }
    }

    /// Returns (creating if needed) the overlay controller for a given screen.
    private func overlayController(for screen: NSScreen) -> OverlayWindowController {
        let id = screen.displayID ?? 0
        if let existing = overlayControllers[id] {
            return existing
        }
        let controller = OverlayWindowController()
        overlayControllers[id] = controller
        return controller
    }

    // MARK: - Grid setup

    private func rebuildGrid(for screen: NSScreen, variant: LayoutVariant) {
        activeScreen = screen
        let config = PreferencesStore.shared.configuration(for: variant)
        let frame = screen.visibleFrameCG
        gridCells = GridCalculator.cells(for: frame, configuration: config)
        let newResolver = SnapResolver(cells: gridCells)
        resolver = newResolver
        shared.resolver = newResolver
    }

    // MARK: - State machine hooks

    private func setupStateMachineHooks() {
        let shared = self.shared

        stateMachine.windowProvider = { _, _ -> TrackedWindow? in
            shared.lastTrackedWindow
        }

        stateMachine.cellProvider = { point -> GridCell? in
            shared.resolver?.cell(at: point)
        }
    }

    // MARK: - Observe state changes

    private func observeStateChanges() {
        stateMachine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: DragState) {
        switch state {

        case .idle:
            handleIdle()

        case .potentialDrag:
            break

        case .shiftDragging(_, let cell):
            handleShiftDragging(cell: cell)

        case .multiCellSelecting(_, let anchor, let current):
            handleMultiCellSelecting(anchor: anchor, current: current)

        case .snapping(let tracked, _):
            handleSnapping(tracked: tracked)
        }
    }

    // MARK: - State handlers

    private func handleIdle() {
        if isOverlayVisible {
            cancelOverlay()
        }
        // Don't restore window — macOS already moved it during drag.
        // Don't clear drag tracking state — user might re-press Shift.
    }

    private func handleShiftDragging(cell: GridCell?) {
        guard let cell else { return }

        if !isOverlayVisible {
            showOverlay()
        }

        activeOverlayController?.updateHighlight(cell: cell)
    }

    private func handleMultiCellSelecting(anchor: GridCell, current: GridCell?) {
        guard let current else { return }

        if !isOverlayVisible {
            showOverlay()
        }

        activeOverlayController?.updateHighlight(region: anchor, to: current)
    }

    private func handleSnapping(tracked: TrackedWindow) {
        // Compute the target rect from the currently highlighted cell(s)
        guard let highlightedCells = activeOverlayController?.overlayView?.highlightedCells,
              !highlightedCells.isEmpty else {
            stateMachine.process(.snapComplete)
            return
        }

        // Compute union rect of highlighted cells
        let targetRect = computeTargetRect(cells: highlightedCells)

        guard let targetRect else {
            stateMachine.process(.snapComplete)
            return
        }

        // Apply the snap
        let success = windowManipulator.setFrame(targetRect, for: tracked.axElement)

        if success, let controller = activeOverlayController,
           let window = controller.overlayWindow,
           let view = controller.overlayView {
            overlayAnimator.successFlash(window: window, overlayView: view)
        } else {
            hideOverlay()
        }

        isOverlayVisible = false
        stateMachine.process(.snapComplete)
    }

    // MARK: - Overlay management

    private func showOverlay() {
        guard let screen = activeScreen ?? NSScreen.main else { return }
        // Grid should already be built from mouseDown, but rebuild if needed
        if gridCells.isEmpty {
            rebuildGrid(for: screen, variant: shared.currentLayoutVariant)
        }

        // If switching screens, hide the previous overlay
        let newController = overlayController(for: screen)
        if let previous = activeOverlayController, previous !== newController {
            previous.hide()
        }
        activeOverlayController = newController

        newController.show(on: screen, gridCells: viewLocalGridCells(for: screen))

        if let window = newController.overlayWindow {
            overlayAnimator.fadeIn(window: window)
        }
        isOverlayVisible = true
    }

    /// Pushes the current `gridCells` to the already-visible overlay without
    /// triggering a fade-in. Used by the Opt-toggle layout-switch path.
    private func pushGridToActiveOverlay(for screen: NSScreen) {
        guard let controller = activeOverlayController else { return }
        controller.show(on: screen, gridCells: viewLocalGridCells(for: screen))
    }

    /// Converts screen-absolute CG cells to view-local coords for the overlay.
    /// The overlay window covers `screen.frame` (full screen including menu bar),
    /// so view (0,0) is the top-left of that frame in CG coords.
    private func viewLocalGridCells(for screen: NSScreen) -> [[CGRect]] {
        let fullFrameCG = screen.fullFrameCG
        return gridCells.map { row in
            row.map { cell in
                CGRect(
                    x: cell.origin.x - fullFrameCG.origin.x,
                    y: cell.origin.y - fullFrameCG.origin.y,
                    width: cell.width,
                    height: cell.height
                )
            }
        }
    }

    private func hideOverlay() {
        guard isOverlayVisible,
              let controller = activeOverlayController,
              let window = controller.overlayWindow else { return }
        overlayAnimator.fadeOut(window: window)
        isOverlayVisible = false
    }

    private func cancelOverlay() {
        guard let controller = activeOverlayController,
              let window = controller.overlayWindow,
              let view = controller.overlayView else { return }
        overlayAnimator.cancelHide(window: window, overlayView: view)
        isOverlayVisible = false
    }

    // MARK: - Helpers

    /// Finds the NSScreen whose frame contains the given CG-coordinate point.
    private func screenContaining(point: CGPoint) -> NSScreen? {
        // Convert CG point to check against each screen's CG frame
        for screen in NSScreen.screens {
            let cgFrame = screen.visibleFrameCG
            // Use a slightly expanded frame to handle edges
            let expanded = cgFrame.insetBy(dx: -1, dy: -1)
            if expanded.contains(point) {
                return screen
            }
        }
        // Fallback to main screen
        return NSScreen.main
    }

    private var activeScreen: NSScreen?

    private func computeTargetRect(cells: Set<GridCell>) -> CGRect? {
        var union: CGRect?
        for cell in cells {
            guard cell.row < gridCells.count,
                  cell.col < gridCells[cell.row].count else { continue }
            let rect = gridCells[cell.row][cell.col]
            union = union.map { $0.union(rect) } ?? rect
        }
        return union
    }

    private func restoreWindowIfNeeded() {
        guard let tracked = shared.pendingRestore else { return }
        windowManipulator.setFrame(tracked.originalFrame, for: tracked.axElement)
        shared.pendingRestore = nil
    }
}

// MARK: - Thread-safe shared state

/// Holds mutable state accessed from both the event queue and the main actor.
/// Uses a lock for safe concurrent access.
private final class SharedState: @unchecked Sendable {
    private let lock = NSLock()

    private var _lastTrackedWindow: TrackedWindow?
    private var _resolver: SnapResolver?
    private var _pendingRestore: TrackedWindow?
    private var _isEnabled: Bool = true
    private var _mouseDownPos: CGPoint?
    private var _isDraggingWithoutShift: Bool = false
    private var _currentLayoutVariant: LayoutVariant = .primary

    var currentLayoutVariant: LayoutVariant {
        get { lock.withLock { _currentLayoutVariant } }
        set { lock.withLock { _currentLayoutVariant = newValue } }
    }

    var lastTrackedWindow: TrackedWindow? {
        get { lock.withLock { _lastTrackedWindow } }
        set { lock.withLock { _lastTrackedWindow = newValue } }
    }

    var resolver: SnapResolver? {
        get { lock.withLock { _resolver } }
        set { lock.withLock { _resolver = newValue } }
    }

    var pendingRestore: TrackedWindow? {
        get { lock.withLock { _pendingRestore } }
        set { lock.withLock { _pendingRestore = newValue } }
    }

    var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    var mouseDownPos: CGPoint? {
        get { lock.withLock { _mouseDownPos } }
        set { lock.withLock { _mouseDownPos = newValue } }
    }

    var isDraggingWithoutShift: Bool {
        get { lock.withLock { _isDraggingWithoutShift } }
        set { lock.withLock { _isDraggingWithoutShift = newValue } }
    }

    func clear() {
        lock.withLock {
            _lastTrackedWindow = nil
            _pendingRestore = nil
            _mouseDownPos = nil
            _isDraggingWithoutShift = false
        }
    }
}

// MARK: - EventMonitorDelegate

extension DragCoordinator: EventMonitorDelegate {
    nonisolated func eventMonitor(_ monitor: EventMonitor, didReceive event: RawMouseEvent) {
        guard shared.isEnabled else { return }

        let currentState = stateMachine.currentState

        // --- Case 1: Shift+mouseDown on title bar → start potential drag ---
        if event.kind == .mouseDown && event.shiftDown {
            let variant: LayoutVariant = event.ctrlDown ? .secondary : .primary
            prepareWindowTracking(at: event.location, variant: variant)
        }

        // --- Case 2: mouseDown without Shift → remember position for late-Shift ---
        if event.kind == .mouseDown && !event.shiftDown {
            shared.mouseDownPos = event.location
            shared.isDraggingWithoutShift = false
        }

        // --- Case 3: mouseDragged without Shift → mark as dragging ---
        if event.kind == .mouseDragged && !event.shiftDown {
            if case .idle = currentState, shared.mouseDownPos != nil {
                shared.isDraggingWithoutShift = true
            }
        }

        // --- Case 4: Shift pressed while mouse button is held → late activation ---
        //
        // Fires in two scenarios:
        //  (a) User started dragging without Shift, then pressed Shift mid-drag
        //      (`isDraggingWithoutShift == true`).
        //  (b) User clicked without Shift, then pressed Shift statically before
        //      any movement (`mouseDownPos != nil`). Without this second case,
        //      the common "click → hold → shift → drag" sequence is silently
        //      ignored because the state machine only transitions to
        //      `.potentialDrag` on `mouseDown + shiftDown`.
        if event.kind == .flagsChanged && event.shiftDown {
            if case .idle = currentState, shared.mouseDownPos != nil {
                // User is already holding the mouse button down (and may have
                // moved it mid-drag). The native OS drag has validated that
                // the click was on a draggable chrome area, so skip the
                // isTitleBar heuristic which is too strict for Finder toolbars,
                // path bars, and other extended window chrome.
                let variant: LayoutVariant = event.ctrlDown ? .secondary : .primary
                prepareWindowTracking(at: event.location, requireTitleBar: false, variant: variant)
                let syntheticDown = RawMouseEvent(
                    kind: .mouseDown, location: event.location,
                    shiftDown: true, ctrlDown: event.ctrlDown, optDown: false,
                    timestamp: event.timestamp
                )
                stateMachine.process(event: syntheticDown)
                let syntheticDrag = RawMouseEvent(
                    kind: .mouseDragged, location: event.location,
                    shiftDown: true, ctrlDown: event.ctrlDown, optDown: false,
                    timestamp: event.timestamp
                )
                stateMachine.process(event: syntheticDrag)
                // If Opt is already held, trigger multi-cell immediately
                if event.optDown {
                    let syntheticFlags = RawMouseEvent(
                        kind: .flagsChanged, location: event.location,
                        shiftDown: true, ctrlDown: event.ctrlDown, optDown: true,
                        timestamp: event.timestamp
                    )
                    stateMachine.process(event: syntheticFlags)
                }
                return
            }
        }

        // --- Case 4b: Ctrl toggle during shiftDragging → switch layout variant ---
        //
        // Dynamic layout switching: while the user is actively dragging in
        // `.shiftDragging`, pressing or releasing Ctrl rebuilds the grid with
        // the other variant and pushes new cells to the visible overlay.
        // Ignored during `.multiCellSelecting` because the anchor cell was
        // recorded in the old grid and would become meaningless after a
        // layout change.
        if event.kind == .flagsChanged && event.shiftDown {
            if case .shiftDragging = currentState {
                let newVariant: LayoutVariant = event.ctrlDown ? .secondary : .primary
                if newVariant != shared.currentLayoutVariant {
                    shared.currentLayoutVariant = newVariant
                    let cursorPoint = event.location
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        let screen = self.screenContaining(point: cursorPoint) ?? NSScreen.main
                        guard let screen else { return }
                        self.rebuildGrid(for: screen, variant: newVariant)
                        self.pushGridToActiveOverlay(for: screen)
                    }
                }
            }
        }

        // --- Case 5: Shift release during active drag → cancel (overlay only, no restore) ---
        if event.kind == .flagsChanged && !event.shiftDown {
            if case .shiftDragging = currentState {
                // Keep isDraggingWithoutShift true so Shift can reactivate
                shared.isDraggingWithoutShift = true
            }
        }

        // --- Case 6: mouseUp → clean up all state ---
        if event.kind == .mouseUp {
            shared.mouseDownPos = nil
            shared.isDraggingWithoutShift = false
        }

        stateMachine.process(event: event)
    }

    /// Detects the window at the given point and prepares for dragging.
    ///
    /// Clears any previously-tracked window before attempting detection, so a
    /// failed detection leaves `lastTrackedWindow` as nil rather than a stale
    /// reference. Without this, a subsequent snap could operate on whichever
    /// window was tracked by the previous drag.
    ///
    /// - Parameter requireTitleBar: When true (default), only accepts the
    ///   window if the cursor is within the `isTitleBar` heuristic area. Case 1
    ///   (Shift+mouseDown from idle) uses this because intent is ambiguous —
    ///   the user may be shift-clicking for non-window-drag reasons. Case 4
    ///   (Shift pressed during an ongoing native drag) passes `false` because
    ///   the user has already committed to a window drag at the OS level and
    ///   the Shift press is an explicit opt-in to snap mode.
    /// - Parameter variant: Layout slot to activate for this drag. Determined
    ///   by the `ctrlDown` flag of the triggering event at drag start.
    private nonisolated func prepareWindowTracking(
        at point: CGPoint,
        requireTitleBar: Bool = true,
        variant: LayoutVariant
    ) {
        shared.lastTrackedWindow = nil
        shared.currentLayoutVariant = variant

        guard let info = windowDetector.windowAtPoint(point) else { return }
        guard !info.isFullscreen else { return }
        if requireTitleBar, !info.isTitleBar(cursorY: point.y) { return }

        shared.lastTrackedWindow = TrackedWindow(
            windowID: info.windowID,
            axElement: info.axElement,
            pid: info.pid,
            originalFrame: info.frame
        )

        let cursorPoint = point
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let screen = self.screenContaining(point: cursorPoint) ?? NSScreen.main
            if let screen {
                self.rebuildGrid(for: screen, variant: variant)
            }
        }
    }

}
