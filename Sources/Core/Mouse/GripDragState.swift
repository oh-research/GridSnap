import Foundation

/// State of the Grip+drag gesture. Mutated from both the CGEventTap
/// callback thread and a background AX-lookup queue, so transitions must
/// happen inside `GripDragCoordinator`'s lock.
///
/// - `idle`: no Grip gesture in progress.
/// - `armed`: Grip+mouseDown was claimed; awaiting either the 5 pt
///   movement threshold (to enter tracking) or a mouseUp / Grip release
///   (to return to idle). `tracked` is populated asynchronously by the
///   AX window lookup; dragged events before that arrives stay armed.
/// - `tracking`: overlay is visible and the highlighted cell follows
///   the cursor; mouseUp snaps the window to the cell (or the union of
///   the multi-cell region), Grip release cancels without snapping.
enum GripDragState: Sendable {
    case idle
    case armed(downPos: CGPoint, tracked: TrackedWindow?, variant: LayoutVariant)
    case tracking(tracked: TrackedWindow, variant: LayoutVariant, phase: TrackingPhase)
}

/// Sub-state within `tracking`. `.single` highlights the single cell
/// under the cursor; `.multi` is entered when the Stretch modifier is
/// added mid-drag and extends the highlight across a rectangular region
/// anchored to the cell where Stretch was first pressed.
enum TrackingPhase: Sendable {
    case single
    case multi(anchor: GridCell)
}
