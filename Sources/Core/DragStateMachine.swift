@preconcurrency import Cocoa
import Combine

// MARK: - DragStateMachine

/// Processes RawMouseEvents and advances the DragState machine.
/// Runs entirely on its own serial DispatchQueue.
/// Produces no side-effects (no overlay, no window manipulation).
///
/// State graph:
///   idle
///     ─ mouseDown + Shift + titleBar → potentialDrag
///   potentialDrag
///     ─ mouseDragged ≥ 5 px           → shiftDragging
///     ─ mouseUp / Shift release        → idle
///     ─ Escape                         → idle
///   shiftDragging
///     ─ mouseDragged (any)             → shiftDragging (update currentCell)
///     ─ mouseUp                        → snapping
///     ─ Shift release                  → idle (abort)
///     ─ Escape                         → idle (abort)
///     ─ window / permission loss       → idle
///   snapping
///     ─ (immediate; consumer drives)   → idle after applying snap
final class DragStateMachine: @unchecked Sendable {

    // MARK: - Types

    enum Input: Sendable {
        /// A raw event from EventMonitor (pre-filtered, any kind).
        case rawEvent(RawMouseEvent)
        /// External cancellation (e.g. Escape key, permission revoked).
        case cancel
        /// Snap was applied by the consumer — return to idle.
        case snapComplete
        /// Window or permission became unavailable.
        case windowLost
    }

    // MARK: - Properties

    private let queue = DispatchQueue(
        label: "com.sniq.statemachine",
        qos: .userInteractive
    )

    /// Published on `queue` — observers must hop to their own queue if needed.
    private let stateSubject: CurrentValueSubject<DragState, Never>
    var statePublisher: AnyPublisher<DragState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var currentState: DragState {
        stateSubject.value
    }

    /// Set by the consumer (e.g. DragCoordinator) to supply the TrackedWindow
    /// when the machine is about to transition to shiftDragging.
    var windowProvider: (@Sendable (_ windowID: CGWindowID, _ pid: pid_t) -> TrackedWindow?)?

    /// Called when the state changes — useful for consumers that don't use Combine.
    var onStateChange: (@Sendable (_ old: DragState, _ new: DragState) -> Void)?

    /// Called to map current cursor point to a GridCell.
    var cellProvider: (@Sendable (_ point: CGPoint) -> GridCell?)?

    // MARK: - Init

    init() {
        stateSubject = CurrentValueSubject(.idle)
    }

    // MARK: - Process

    func process(_ input: Input) {
        queue.async { [self] in
            let old = stateSubject.value
            let new = reduce(state: old, input: input)
            if !statesEqual(old, new) {
                stateSubject.send(new)
                onStateChange?(old, new)
            }
        }
    }

    // Convenience for RawMouseEvent
    func process(event: RawMouseEvent) {
        process(.rawEvent(event))
    }

    // MARK: - Reducer (runs on queue)

    private func reduce(state: DragState, input: Input) -> DragState {
        switch (state, input) {

        // ── idle ────────────────────────────────────────────────────────────

        case (.idle, .rawEvent(let e)) where e.kind == .mouseDown && e.shiftDown:
            // We don't yet have the TrackedWindow; store minimal info.
            // The windowProvider will be called once drag starts.
            return .potentialDrag(
                mouseDownPos: e.location,
                windowID: 0,     // placeholder — resolved on first drag
                pid: 0           // placeholder
            )

        case (.idle, _):
            return .idle

        // ── potentialDrag ────────────────────────────────────────────────

        case (.potentialDrag(let downPos, _, _), .rawEvent(let e)) where e.kind == .mouseDragged:
            let dist = distance(downPos, e.location)
            // Skip 5px threshold if downPos == location (late Shift activation,
            // where synthetic events use the same position)
            let isLateActivation = (downPos == e.location)
            guard dist >= 5 || isLateActivation else { return state }

            guard let provider = windowProvider,
                  let tracked = provider(0, 0)
            else {
                return .idle
            }
            let cell = cellProvider?(e.location)
            return .shiftDragging(trackedWindow: tracked, currentCell: cell)

        case (.potentialDrag, .rawEvent(let e)) where e.kind == .mouseUp:
            return .idle

        case (.potentialDrag, .rawEvent(let e)) where e.kind == .flagsChanged && !e.shiftDown:
            return .idle

        case (.potentialDrag, .cancel), (.potentialDrag, .windowLost):
            return .idle

        case (.potentialDrag, _):
            return state

        // ── shiftDragging ────────────────────────────────────────────────

        case (.shiftDragging(let tracked, _), .rawEvent(let e)) where e.kind == .mouseDragged:
            let cell = cellProvider?(e.location)
            return .shiftDragging(trackedWindow: tracked, currentCell: cell)

        // Cmd pressed → enter multi-cell with current cell as anchor
        case (.shiftDragging(let tracked, let cell), .rawEvent(let e))
            where e.kind == .flagsChanged && e.shiftDown && e.cmdDown:
            guard let cell else { return state }
            return .multiCellSelecting(trackedWindow: tracked, anchorCell: cell, currentCell: cell)

        case (.shiftDragging(let tracked, let cell), .rawEvent(let e)) where e.kind == .mouseUp:
            guard let cell else { return .idle }
            let targetRect = tracked.originalFrame
            _ = cell
            return .snapping(trackedWindow: tracked, targetRect: targetRect)

        case (.shiftDragging, .rawEvent(let e)) where e.kind == .flagsChanged && !e.shiftDown:
            return .idle   // Shift released — abort

        case (.shiftDragging, .cancel), (.shiftDragging, .windowLost):
            return .idle

        case (.shiftDragging, _):
            return state

        // ── multiCellSelecting ──────────────────────────────────────────

        case (.multiCellSelecting(let tracked, let anchor, _), .rawEvent(let e))
            where e.kind == .mouseDragged:
            let cell = cellProvider?(e.location)
            return .multiCellSelecting(trackedWindow: tracked, anchorCell: anchor, currentCell: cell)

        // Cmd released (Shift still held) → back to single cell
        case (.multiCellSelecting(let tracked, _, _), .rawEvent(let e))
            where e.kind == .flagsChanged && e.shiftDown && !e.cmdDown:
            let cell = cellProvider?(e.location)
            return .shiftDragging(trackedWindow: tracked, currentCell: cell)

        // Shift released → cancel
        case (.multiCellSelecting, .rawEvent(let e))
            where e.kind == .flagsChanged && !e.shiftDown:
            return .idle

        // mouseUp → snap to multi-cell region
        case (.multiCellSelecting(let tracked, _, let cell), .rawEvent(let e))
            where e.kind == .mouseUp:
            guard let cell else { return .idle }
            let targetRect = tracked.originalFrame
            _ = cell
            return .snapping(trackedWindow: tracked, targetRect: targetRect)

        case (.multiCellSelecting, .cancel), (.multiCellSelecting, .windowLost):
            return .idle

        case (.multiCellSelecting, _):
            return state

        // ── snapping ────────────────────────────────────────────────────

        case (.snapping, .snapComplete):
            return .idle

        case (.snapping, .cancel), (.snapping, .windowLost):
            return .idle

        case (.snapping, _):
            return state

        // ── catch-all ────────────────────────────────────────────────────

        default:
            return state
        }
    }

    // MARK: - Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Cheap structural equality without making DragState Equatable.
    private func statesEqual(_ a: DragState, _ b: DragState) -> Bool {
        switch (a, b) {
        case (.idle, .idle): return true
        case (.potentialDrag(let ap, let aw, let apid),
              .potentialDrag(let bp, let bw, let bpid)):
            return ap == bp && aw == bw && apid == bpid
        case (.shiftDragging(_, let ac), .shiftDragging(_, let bc)):
            return ac == bc
        case (.multiCellSelecting(_, let aa, let ac), .multiCellSelecting(_, let ba, let bc)):
            return aa == ba && ac == bc
        case (.snapping(_, let ar), .snapping(_, let br)):
            return ar == br
        default: return false
        }
    }
}
