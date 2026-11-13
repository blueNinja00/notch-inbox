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
        let outline = model.outline(level)
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

    /// The keys of a key press, as a shortcut.
    static func combo(for event: NSEvent) -> KeyCombo {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let code = Int(event.keyCode)
        return KeyCombo(code: code, symbol: KeyCombo.symbol(code: code, characters: event.charactersIgnoringModifiers),
                        command: flags.contains(.command), control: flags.contains(.control),
                        option: flags.contains(.option), shift: flags.contains(.shift))
    }

    /// While a shortcut is being set: Esc gives up, Delete takes its key off, and any
    /// other keys become its key if they can be one (if not, Settings says why and waits).
    private func record(_ event: NSEvent, for action: KeyAction) {
        let combo = Self.combo(for: event)
        let bare = !combo.hasModifier && !combo.shift
        if combo.code == KeyCombo.escape && bare {
            model.recordingKey = nil
            return
        }
        if (combo.code == KeyCombo.delete || combo.code == KeyCombo.forwardDelete) && bare {
            AppSettings.shared.clearKey(action)
            model.keyNote = "“\(action.title)” has no key now."
            model.recordingKey = nil
            return
        }
        if let problem = combo.problem {
            model.keyNote = problem
            return
        }
        model.keyNote = AppSettings.shared.setKey(combo, for: action)
        model.recordingKey = nil
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let panel = panel, panel.isKeyWindow, model.level != .rest else { return event }

        // Setting a shortcut in Settings: the next keys pressed become it.
        if let action = model.recordingKey {
            record(event, for: action)
            return nil
        }

        // In the tour, the arrow keys (and Return) turn the pages, and Esc leaves it for the
        // primary menu, where it stays on offer.
        if model.tool == .tour && (model.level == .lanes || model.level == .detail) {
            if event.keyCode == 53 {
                model.goHome()
                return nil
            }
            if !(panel.firstResponder is NSText) && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                switch event.keyCode {
                case 123: // left arrow
                    model.tourBack()
                    return nil
                case 124, 36, 76: // right arrow, Return, Enter
                    model.tourNext()
                    return nil
                default:
                    break
                }
            }
        }

        if event.keyCode == 53 { // Escape steps back one level: email → inboxes → tools → closed
            // In the timetable, Esc first closes the side panel you're editing in.
            if model.tool == .timetable && model.timetableEdit != nil {
                model.timetableEdit = nil
                return nil
            }
            // In the planner too.
            if model.tool == .planner && model.plannerEdit != nil {
                model.closePlannerEdit()
                return nil
            }
            // And in Bookmarks.
            if model.tool == .bookmarks && model.bookmarkEdit != nil {
                model.bookmarkEdit = nil
                return nil
            }
            // And in Assignments.
            if model.tool == .assignments && model.assignmentOpen != nil {
                model.assignmentOpen = nil
                return nil
            }
            // In the agent room, Esc first steps back from a report or a recipe to its list.
            if model.tool == .agents && (model.level == .lanes || model.level == .detail) && model.stepBackInAgents() {
                return nil
            }
            // In Mail, Esc first closes the search box.
            if model.tool == .mail && model.searching {
                model.endSearch()
                return nil
            }
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

        // Your shortcuts (Settings → Shortcuts). One that also edits text (⌘⌫, ⌘↑…) is
        // left to the text while there's some in the box you're typing in.
        let pressed = Self.combo(for: event)
        if pressed.hasModifier || KeyCombo.functionKeys.contains(pressed.code) {
            let typed = (panel.firstResponder as? NSText)?.string ?? ""
            let inAgents = model.tool == .agents && (model.level == .lanes || model.level == .detail)
            if !(pressed.editsText && !typed.isEmpty),
               let action = AppSettings.shared.keybinds.action(for: pressed, inAgents: inAgents),
               model.perform(action) {
                return nil
            }
        }

        // The app has no menu bar of its own, so copy, paste, select all and undo are
        // passed to the text you're editing here.
        if panel.firstResponder is NSText,
           event.modifierFlags.intersection([.command, .control, .option]) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector?
            switch key {
            case "x": action = #selector(NSText.cut(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            default: action = nil
            }
            if let action = action, NSApp.sendAction(action, to: nil, from: panel) {
                return nil
            }
        }

        // Leave every other key alone while you're typing a reply.
        if panel.firstResponder is NSText { return event }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        // Mail's shortcuts only apply in Mail.
        guard model.tool == .mail, model.level != .peek, modifiers.isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }

        switch key {
        case "1", "2", "3":
            model.open(accountAt: (Int(key) ?? 1) - 1)
            return nil
        case "e" where model.level == .detail && model.canAct:
            model.archiveOpen()
            return nil
        case "u" where model.level == .detail:
            if let id = model.openMessageID {
                model.toggleRead(id)
            }
            return nil
        case "/":
            model.startSearch()
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
