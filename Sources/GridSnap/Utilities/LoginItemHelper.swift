import ServiceManagement

/// Wraps SMAppService to register/unregister the app as a login item.
@MainActor
enum LoginItemHelper {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers the app as a login item. Returns true on success.
    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            return false
        }
    }

    /// Unregisters the app from login items. Returns true on success.
    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            return false
        }
    }

    /// Sets the login item state to `enabled`.
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }
}
