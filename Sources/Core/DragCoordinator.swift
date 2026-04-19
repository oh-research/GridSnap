@preconcurrency import Cocoa
import Combine

/// Owns the shared `EventMonitor` and wires the keyboard- and Grip-drag
/// coordinators into it. Surfaces accessibility-permission errors on the
/// menu bar. Kept as a thin orchestrator after the legacy Shift+titlebar
/// state machine was folded into `GripDragCoordinator` (unified
/// Shift+anywhere gesture).
@MainActor
final class DragCoordinator {

    private let eventMonitor = EventMonitor()
    private var cancellables = Set<AnyCancellable>()

    /// Injected by AppDelegate so permission errors can be shown in the menu bar.
    weak var statusBarController: StatusBarController?

    // MARK: - Lifecycle

    func start() {
        observeAccessibility()
        CustomSnapCoordinator.shared.wire(to: eventMonitor)
        GripDragCoordinator.shared.wire(to: eventMonitor)
        eventMonitor.onTapCreationFailure = { [weak self] in
            Task { @MainActor [weak self] in
                self?.statusBarController?.showError(
                    "Could not create event tap. Check Accessibility permission."
                )
            }
        }
        eventMonitor.start()
    }

    func stop() {
        GripDragCoordinator.shared.unwire(from: eventMonitor)
        CustomSnapCoordinator.shared.unwire(from: eventMonitor)
        eventMonitor.stop()
        cancellables.removeAll()
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
                    self.statusBarController?.showError(
                        "Accessibility permission required for window snapping."
                    )
                }
            }
            .store(in: &cancellables)
    }
}
