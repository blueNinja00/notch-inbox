import AppKit
import Combine
import SwiftUI

/// Borderless, transparent panel that sits above the menu bar at the top of the screen.
final class NotchPanel: NSPanel {
    convenience init(frame: NSRect) {
        self.init(contentRect: frame,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Lets the reply box take typing without pulling focus away from your current app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Stops AppKit from nudging the window down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that reacts to the very first click, even before the panel has
/// focus, so a single click on the peek opens the lanes.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the panel, keeps it pinned to the notch, and decides when the mouse
/// reaches it (over the black shape) or passes through to the apps below.
final class NotchWindowController {
    private let model: NotchModel
    private var screen: NSScreen
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var subscriptions = Set<AnyCancellable>()
    private var pendingHover: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    init(model: NotchModel, screen: NSScreen) {
        self.model = model
        self.screen = screen
    }

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        let frame = panelFrame()
        let panel = NotchPanel(frame: frame)
        let host = NotchHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel

        installMonitors()

        model.$level
            .removeDuplicates()
            .sink { [weak self] level in self?.levelDidChange(to: level) }
            .store(in: &subscriptions)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenDidChange()
        }
    }

    // MARK: Geometry

    private func panelFrame() -> NSRect {
        let size = model.metrics.windowSize
        let screenFrame = screen.frame
        return NSRect(x: screenFrame.midX - size.width / 2,
                      y: screenFrame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// The visible black shape for the current level, in screen coordinates.
    private func hotRect() -> NSRect {
        let level = model.level
        let outline = model.metrics.outlineSize(level, showEars: model.totalUnread > 0)
        let screenFrame = screen.frame
        let rect = NSRect(x: screenFrame.midX - outline.width / 2,
                          y: screenFrame.maxY - outline.height,
                          width: outline.width,
                          height: outline.height)
        // A little slack around the closed notch makes it easier to hover.
        return level == .rest ? rect.insetBy(dx: -6, dy: -4) : rect
    }

    // MARK: Mouse and keyboard

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.mouseMoved()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.clickedElsewhere()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self = self else { return event }
            return self.handleKey(event)
        }) {
            monitors.append(monitor)
        }
    }

    private func mouseMoved() {
        guard let panel = panel else { return }
        let inside = hotRect().contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }

        switch model.level {
        case .rest:
            if inside {
                schedule(after: 0.08) { [weak self] in self?.model.peek() }
            } else {
                cancelPending()
            }
        case .peek:
            if inside {
                cancelPending()
            } else {
                schedule(after: 0.2) { [weak self] in self?.model.unpeek() }
            }
        case .lanes, .detail:
            break
        }
    }

    /// Clicks anywhere outside the open panel close it.
    private func clickedElsewhere() {
        guard model.level != .rest else { return }
        if !hotRect().contains(NSEvent.mouseLocation) {
            model.close()
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let panel = panel, panel.isKeyWindow, model.level != .rest else { return event }

        if event.keyCode == 53 { // Escape steps back one level
            if model.level == .detail {
                model.back()
            } else {
                model.close()
            }
            return nil
        }

        // Leave every other key alone while you're typing a reply.
        if panel.firstResponder is NSText { return event }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }

        switch key {
        case "1", "2", "3":
            model.open(accountAt: (Int(key) ?? 1) - 1)
            return nil
        case "e" where model.level == .detail && model.canAct:
            model.archiveOpen()
            return nil
        case "u" where model.level == .detail && model.canAct:
            model.markOpenUnread()
            return nil
        case "o" where model.level == .detail:
            model.openInGmail()
            return nil
        default:
            return event
        }
    }

    // MARK: Level changes

    private func levelDidChange(to level: NotchLevel) {
        cancelPending()
        // @Published announces the change just before storing it, so refresh on the next turn.
        DispatchQueue.main.async { [weak self] in
            self?.refreshMousePassThrough()
            if level == .rest {
                self?.giveKeyboardBack()
            }
        }
    }

    private func refreshMousePassThrough() {
        guard let panel = panel else { return }
        panel.ignoresMouseEvents = !hotRect().contains(NSEvent.mouseLocation)
    }

    /// If the reply box had keyboard focus, hand typing back to the app underneath.
    private func giveKeyboardBack() {
        guard let panel = panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func screenDidChange() {
        guard let placement = NotchPlacement.detect() else { return }
        screen = placement.screen
        model.metrics = placement.metrics
        panel?.setFrame(panelFrame(), display: true)
        refreshMousePassThrough()
    }

    // MARK: Hover timing

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        guard pendingHover == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingHover = nil
            action()
        }
        pendingHover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pendingHover?.cancel()
        pendingHover = nil
    }
}
