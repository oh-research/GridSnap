import Cocoa

func debugLog(_ msg: String) {
    let logFile = NSHomeDirectory() + "/gridsnap-debug.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
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
