import AppKit
import Combine
import SwiftUI

/// Borderless, transparent panel that sits above the menu bar at the top of a screen.
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
        // Every desktop (Space), including full-screen apps.
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

/// Owns one screen's panel, keeps it pinned to that screen's notch, and decides when
/// the mouse reaches it (over the black shape) or passes through to the apps below.
final class NotchWindowController {
    let model: NotchModel
    private(set) var screen: NSScreen
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var subscriptions = Set<AnyCancellable>()
    private var pendingHover: DispatchWorkItem?
    private var spaceObserver: NSObjectProtocol?

    init(model: NotchModel, placement: NotchPlacement) {
        self.model = model
        self.screen = placement.screen
    }

    deinit {
        close()
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

        // Belt and braces: bring the panel forward whenever you switch desktops.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.panel?.orderFrontRegardless()
        }
    }

    /// The screen was rearranged, changed resolution, or its notch size changed.
    func move(to placement: NotchPlacement) {
        screen = placement.screen
        if model.metrics != placement.metrics {
            model.metrics = placement.metrics
        }
        panel?.setFrame(panelFrame(), display: true)
        refreshMousePassThrough()
    }

    /// Takes the panel down, e.g. when its display is unplugged.
    func close() {
        cancelPending()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        subscriptions.removeAll()
        panel?.orderOut(nil)
        panel = nil
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
        // Minimised to the mail icon: the closed notch lets every click and hover through.
        if model.minimised && level == .rest {
            return .zero
        }
        let outline = model.metrics.outlineSize(level, ears: model.restEars)
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
            if inside || model.homePinned {
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

        if event.keyCode == 53 { // Escape steps back one level: email → inboxes → tools → closed
            switch model.level {
            case .detail:
                model.back()
            case .lanes:
                model.goHome()
            default:
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
