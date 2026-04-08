import Cocoa
import os

/// Unified logger for GridSnap. Debug-level messages do not persist to disk;
/// to stream them live during development, run:
///
///     log stream --predicate 'subsystem == "com.ohresearch.gridsnap"' --level debug
private let appLogger = Logger(subsystem: "com.ohresearch.gridsnap", category: "GridSnap")

/// Emits a debug message via the unified logging system.
///
/// Replaces the previous file-based logger that wrote to `~/gridsnap-debug.log`
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
        debugLog("[GridSnap] launched")
        statusBarController.setup()
        dragCoordinator.statusBarController = statusBarController

        if PreferencesStore.shared.onboardingCompleted {
            AccessibilityManager.shared.checkPermission()
        }
        debugLog("[GridSnap] Accessibility trusted: \(AccessibilityManager.shared.isTrusted)")

        debugLog("[GridSnap] onboardingCompleted: \(PreferencesStore.shared.onboardingCompleted), allPermissionsGranted: \(AccessibilityManager.shared.allPermissionsGranted)")
        if !PreferencesStore.shared.onboardingCompleted || !AccessibilityManager.shared.allPermissionsGranted {
            debugLog("[GridSnap] Will show onboarding")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                debugLog("[GridSnap] Calling showOnboarding()")
                statusBarController.showOnboarding()
                debugLog("[GridSnap] showOnboarding() returned")
            }
        }

        if AccessibilityManager.shared.allPermissionsGranted {
            debugLog("[GridSnap] Starting DragCoordinator")
            dragCoordinator.start()
        } else {
            debugLog("[GridSnap] Waiting for permissions")
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
