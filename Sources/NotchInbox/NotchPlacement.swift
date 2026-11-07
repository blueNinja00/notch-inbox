import AppKit

/// Which screen the notch lives on, and how big it is.
struct NotchPlacement {
    let screen: NSScreen
    let metrics: NotchMetrics

    /// Prefers the built-in display with a camera notch. Macs without one get a
    /// notch-sized pill hanging from the menu bar instead.
    static func detect() -> NotchPlacement? {
        let screens = NSScreen.screens
        guard let fallback = NSScreen.main ?? screens.first else { return nil }
        let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? fallback

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let metrics = NotchMetrics(notchWidth: width, notchHeight: screen.safeAreaInsets.top, hasNotch: true)
            return NotchPlacement(screen: screen, metrics: metrics)
        }

        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let metrics = NotchMetrics(notchWidth: 190, notchHeight: max(menuBarHeight, 24), hasNotch: false)
        return NotchPlacement(screen: screen, metrics: metrics)
    }
}
