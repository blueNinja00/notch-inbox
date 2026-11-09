import AppKit

/// Where a notch panel sits: which screen, and how big that screen's notch is.
struct NotchPlacement {
    let screen: NSScreen
    let metrics: NotchMetrics

    var displayID: CGDirectDisplayID { screen.displayID }

    /// One placement per connected screen.
    static func allScreens() -> [NotchPlacement] {
        NSScreen.screens.map { placement(for: $0) }
    }

    /// Screens with a camera notch use its real size. Others (external displays, older
    /// Macs) get a notch-sized pill hanging from the top edge, in the same place.
    static func placement(for screen: NSScreen) -> NotchPlacement {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let metrics = NotchMetrics(notchWidth: width, notchHeight: screen.safeAreaInsets.top, hasNotch: true,
                                       screenSize: screen.frame.size)
            return NotchPlacement(screen: screen, metrics: metrics)
        }

        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let metrics = NotchMetrics(notchWidth: 190, notchHeight: max(menuBarHeight, 24), hasNotch: false,
                                   screenSize: screen.frame.size)
        return NotchPlacement(screen: screen, metrics: metrics)
    }
}

extension NSScreen {
    /// Stable ID for a display, so its panel survives resolution and arrangement changes.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
