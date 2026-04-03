import Cocoa

extension NSScreen {
    /// The CoreGraphics display ID for this screen.
    var displayID: CGDirectDisplayID? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return id
    }
}

extension NSScreen {
    /// NSScreen.visibleFrame (Cocoa 좌하단 원점) → CG 좌표계 (좌상단 원점) 변환
    var visibleFrameCG: CGRect {
        guard let primary = NSScreen.screens.first else { return visibleFrame }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: visibleFrame.origin.x,
            y: primaryHeight - visibleFrame.origin.y - visibleFrame.height,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    /// NSScreen.frame (전체 화면, 메뉴바 포함) → CG 좌표계 (좌상단 원점) 변환
    var fullFrameCG: CGRect {
        guard let primary = NSScreen.screens.first else { return frame }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
