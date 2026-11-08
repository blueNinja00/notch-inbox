import AppKit
import SwiftUI

/// Notch Inbox minimised: a small notch-shaped tab with a mail icon, hanging from the top
/// edge of the screen like the real notch. Drag it along the top (to another screen too);
/// it remembers where. Click it to open the primary menu at the notch; right-click it for
/// the app menu.
final class MailIconController {
    var onOpen: (() -> Void)?
    var menu: (() -> NSMenu?)?

    private var panel: NotchPanel?
    private static let positionKey = "miniNotchPosition"
    /// The tab's body; the window adds the inward-curving shoulders on each side.
    private static let bodyWidth: CGFloat = 52
    private static let shoulder: CGFloat = 6

    var isShown: Bool { panel != nil }

    /// The screen the tab is on, so the primary menu opens at that screen's notch.
    var screen: NSScreen? {
        guard let frame = panel?.frame else { return nil }
        return MailIconController.screen(atX: frame.midX, nearY: frame.maxY)
    }

    func show() {
        guard panel == nil else {
            keepOnScreen()
            return
        }
        let panel = NotchPanel(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        let dragArea = MailIconDragView(frame: panel.contentRect(forFrameRect: panel.frame))
        dragArea.onClick = { [weak self] in
            self?.onOpen?()
        }
        dragArea.onDrag = { [weak self] in
            self?.followPointer()
        }
        dragArea.onDragEnded = { [weak self] in
            self?.keepOnScreen()
        }
        dragArea.contextMenu = { [weak self] in
            self?.menu?()
        }
        let picture = PassThroughHostingView(rootView: MiniNotchView(shoulder: MailIconController.shoulder))
        picture.frame = dragArea.bounds
        picture.autoresizingMask = [.width, .height]
        dragArea.addSubview(picture)
        dragArea.autoresizingMask = [.width, .height]
        panel.contentView = dragArea
        self.panel = panel

        place(atX: MailIconController.savedX(), on: MailIconController.savedScreen())
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// Snaps the tab to the top edge of the screen it's over, fully on screen and clear of
    /// a camera notch, and remembers where it is.
    func keepOnScreen() {
        guard let panel = panel else { return }
        let frame = panel.frame
        place(atX: frame.midX, on: MailIconController.screen(atX: frame.midX, nearY: frame.maxY))
    }

    /// While dragging: follow the pointer along the top of whichever screen it's on.
    private func followPointer() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? MailIconController.screen(atX: mouse.x, nearY: mouse.y)
        place(atX: mouse.x, on: screen, save: false, avoidNotch: false)
    }

    private func place(atX centerX: CGFloat, on screen: NSScreen?, save: Bool = true, avoidNotch: Bool = true) {
        guard let panel = panel, let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let height = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        let width = MailIconController.bodyWidth + MailIconController.shoulder * 2
        var x = centerX - width / 2

        if avoidNotch {
            // Under a camera notch the tab would vanish: move it to whichever side is nearer.
            let placement = NotchPlacement.placement(for: screen)
            if placement.metrics.hasNotch {
                let half = placement.metrics.notchWidth / 2 + 6
                let notch = (screen.frame.midX - half)...(screen.frame.midX + half)
                if notch.overlaps(x...(x + width)) {
                    x = centerX < screen.frame.midX ? notch.lowerBound - width : notch.upperBound
                }
            }
        }
        x = min(max(x, screen.frame.minX), screen.frame.maxX - width)
        panel.setFrame(NSRect(x: x, y: screen.frame.maxY - height, width: width, height: height), display: true)

        if save {
            // Saved as a share of the screen's width, so it lands in the same spot after the
            // screen's resolution or arrangement changes.
            let share = (x + width / 2 - screen.frame.minX) / screen.frame.width
            UserDefaults.standard.set(["share": Double(share), "screen": Double(screen.displayID)],
                                      forKey: MailIconController.positionKey)
        }
    }

    private static func screen(atX x: CGFloat, nearY y: CGFloat) -> NSScreen? {
        let columns = NSScreen.screens.filter { $0.frame.minX <= x && x < $0.frame.maxX }
        return columns.min { abs($0.frame.maxY - y) < abs($1.frame.maxY - y) } ?? NSScreen.main
    }

    private static func savedScreen() -> NSScreen? {
        let saved = UserDefaults.standard.dictionary(forKey: positionKey)
        if let id = saved?["screen"] as? Double,
           let screen = NSScreen.screens.first(where: { Double($0.displayID) == id }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Where the tab was left; at first, just right of the notch.
    private static func savedX() -> CGFloat {
        guard let screen = savedScreen() else { return 0 }
        if let share = UserDefaults.standard.dictionary(forKey: positionKey)?["share"] as? Double {
            return screen.frame.minX + CGFloat(share) * screen.frame.width
        }
        let notch = NotchPlacement.placement(for: screen).metrics.notchWidth
        return screen.frame.midX + notch / 2 + 12 + bodyWidth / 2 + shoulder
    }
}

/// The minimised tab: notch-black, flat against the top edge, with a mail icon. No numbers.
struct MiniNotchView: View {
    let shoulder: CGFloat

    var body: some View {
        ZStack {
            NotchShape(bottomRadius: 9, shoulder: shoulder)
                .fill(Color.black)
            Image(systemName: "envelope.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// Lets the drag area below it handle every click.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Click to open, drag to slide along the top, right-click for the menu.
final class MailIconDragView: NSView {
    var onClick: (() -> Void)?
    var onDrag: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var contextMenu: (() -> NSMenu?)?

    private var grabbedAt: NSPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        grabbedAt = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grabbedAt = grabbedAt else { return }
        let now = NSEvent.mouseLocation
        if !dragging && abs(now.x - grabbedAt.x) < 3 && abs(now.y - grabbedAt.y) < 3 {
            return // still a click, not a drag
        }
        dragging = true
        onDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        let wasPressed = grabbedAt != nil
        grabbedAt = nil
        dragging = false
        if wasDragging {
            onDragEnded?()
        } else if wasPressed {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenu?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}
