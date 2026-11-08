import AppKit
import SwiftUI

/// Notch Inbox minimised: a small mail icon with the unread count, floating above other
/// windows. Drag it anywhere (it remembers where); click it to open your inboxes at the
/// notch; right-click it for the app menu.
final class MailIconController {
    var onOpen: (() -> Void)?
    var menu: (() -> NSMenu?)?

    private var panel: NSPanel?
    private let badge = MailIconBadge()
    private static let originKey = "mailIconOrigin"
    private static let size = CGSize(width: 64, height: 54)

    var isShown: Bool { panel != nil }

    /// The screen the icon is on, so the inboxes open at that screen's notch.
    var screen: NSScreen? {
        guard let frame = panel?.frame else { return nil }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? panel?.screen
    }

    func setUnread(_ count: Int) {
        if badge.unread != count {
            badge.unread = count
        }
    }

    func show() {
        guard panel == nil else {
            keepOnScreen()
            return
        }
        let frame = NSRect(origin: MailIconController.startingOrigin(), size: MailIconController.size)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let dragArea = MailIconDragView(frame: NSRect(origin: .zero, size: MailIconController.size))
        dragArea.onClick = { [weak self] in
            self?.onOpen?()
        }
        dragArea.onDragEnded = { [weak self] in
            self?.keepOnScreen()
        }
        dragArea.contextMenu = { [weak self] in
            self?.menu?()
        }
        let picture = PassThroughHostingView(rootView: MailIconView(badge: badge))
        picture.frame = dragArea.bounds
        picture.autoresizingMask = [.width, .height]
        dragArea.addSubview(picture)
        panel.contentView = dragArea

        panel.orderFrontRegardless()
        self.panel = panel
        keepOnScreen()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// Keeps the icon fully on a screen (after a drag, or when a display goes away) and
    /// remembers where it is.
    func keepOnScreen() {
        guard let panel = panel else { return }
        var origin = panel.frame.origin
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let visible = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        }
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: MailIconController.originKey)
    }

    /// Where the icon was left, if that's still on a screen; otherwise the top right of
    /// the main screen, just under the menu bar.
    private static func startingOrigin() -> NSPoint {
        if let saved = UserDefaults.standard.array(forKey: originKey) as? [Double], saved.count == 2 {
            let origin = NSPoint(x: saved[0], y: saved[1])
            let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            if NSScreen.screens.contains(where: { $0.frame.contains(center) }) {
                return origin
            }
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 10)
    }
}

final class MailIconBadge: ObservableObject {
    @Published var unread = 0
}

/// The round mail icon with a red unread badge.
struct MailIconView: View {
    @ObservedObject var badge: MailIconBadge

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.black)
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .overlay(
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                )
                .frame(width: 40, height: 40)
                .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(EdgeInsets(top: 0, leading: 6, bottom: 6, trailing: 0))

            if badge.unread > 0 {
                Text(UnreadText.format(badge.unread))
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Color(hex: 0xFF453A)))
            }
        }
        .frame(width: 64, height: 54)
    }
}

/// Lets the drag area below it handle every click.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Click to open, drag to move, right-click for the menu.
final class MailIconDragView: NSView {
    var onClick: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var contextMenu: (() -> NSMenu?)?

    private var grabbedAt: NSPoint?
    private var startOrigin: NSPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        grabbedAt = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let grabbedAt = grabbedAt, let startOrigin = startOrigin else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - grabbedAt.x
        let dy = now.y - grabbedAt.y
        if !dragging && abs(dx) < 3 && abs(dy) < 3 {
            return // still a click, not a drag
        }
        dragging = true
        window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        let wasPressed = grabbedAt != nil
        grabbedAt = nil
        startOrigin = nil
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
