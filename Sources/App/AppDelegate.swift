import Cocoa
import os

/// Unified logger for Sniq. Debug-level messages do not persist to disk;
/// to stream them live during development, run:
///
///     log stream --predicate 'subsystem == "com.ohresearch.sniq"' --level debug
private let appLogger = Logger(subsystem: "com.ohresearch.sniq", category: "Sniq")

/// Emits a debug message via the unified logging system.
///
/// Replaces the previous file-based logger that wrote to `~/sniq-debug.log`
/// on every call — that approach bloated the user's home directory in release
/// builds. `os.Logger.debug` messages are not persisted unless a caller is
/// actively streaming them (via `log stream` or Console.app).
func debugLog(_ msg: String) {
    appLogger.debug("\(msg, privacy: .public)")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBarController = StatusBarController()
    private let dragCoordinator = DragCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Sniq] launched")
        statusBarController.setup()
        dragCoordinator.statusBarController = statusBarController

        if PreferencesStore.shared.onboardingCompleted {
            AccessibilityManager.shared.checkPermission()
        }
        debugLog("[Sniq] Accessibility trusted: \(AccessibilityManager.shared.isTrusted)")

        debugLog("[Sniq] onboardingCompleted: \(PreferencesStore.shared.onboardingCompleted), allPermissionsGranted: \(AccessibilityManager.shared.allPermissionsGranted)")
        if !PreferencesStore.shared.onboardingCompleted || !AccessibilityManager.shared.allPermissionsGranted {
            debugLog("[Sniq] Will show onboarding")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                debugLog("[Sniq] Calling showOnboarding()")
                statusBarController.showOnboarding()
                debugLog("[Sniq] showOnboarding() returned")
            }
        }

        if AccessibilityManager.shared.allPermissionsGranted {
            debugLog("[Sniq] Starting DragCoordinator")
            dragCoordinator.start()
        } else {
            debugLog("[Sniq] Waiting for permissions")
            AccessibilityManager.shared.startPolling()
            startWhenTrusted()
        }
    }

    private func startWhenTrusted() {
        // Observe isTrusted changes
        // Start when both permissions are granted
        AccessibilityManager.shared.$isTrusted
            .combineLatest(AccessibilityManager.shared.$canListenEvents)
            .filter { $0 && $1 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dragCoordinator.start()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}

import Combine
