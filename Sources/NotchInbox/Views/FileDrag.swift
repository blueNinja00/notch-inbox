import AppKit
import SwiftUI

/// Somewhere files can be dragged out of the notch the way Finder drags them: the drag
/// carries each file's own address straight away, which is what a browser (Gmail's attach
/// area, a chat in a web page) and other apps look for. (SwiftUI's own file drags hand
/// over the files only when asked, which Finder accepts and browsers don't.)
///
/// It goes over whatever it's for (a file's icon, a row) and handles that area's clicks
/// too: a click, a double-click and a right-click can each have something to do.
struct FileDragArea: NSViewRepresentable {
    /// The files to drag, read when the drag starts.
    let urls: () -> [URL]
    var click: (() -> Void)? = nil
    var doubleClick: (() -> Void)? = nil
    /// The right-click menu.
    var menu: (() -> NSMenu?)? = nil
    /// Told when the pointer comes over it and leaves.
    var hover: ((Bool) -> Void)? = nil
    /// Told when a drag starts and ends (so the notch can stay open meanwhile).
    var started: (() -> Void)? = nil
    var ended: (() -> Void)? = nil
    var tip = ""

    func makeNSView(context: Context) -> FileDragView {
        let view = FileDragView()
        update(view)
        return view
    }

    func updateNSView(_ view: FileDragView, context: Context) {
        update(view)
    }

    private func update(_ view: FileDragView) {
        view.urls = urls
        view.onClick = click
        view.onDoubleClick = doubleClick
        view.menuProvider = menu
        view.onHover = hover
        view.onStart = started
        view.onEnd = ended
        view.toolTip = tip.isEmpty ? nil : tip
    }
}

/// The AppKit side of `FileDragArea`.
final class FileDragView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onHover: ((Bool) -> Void)?
    var onStart: (() -> Void)?
    var onEnd: (() -> Void)?

    private var downAt: NSPoint?
    private var dragging = false
    private var tracking: NSTrackingArea?

    /// How far the pointer moves before a press becomes a drag.
    static let threshold: CGFloat = 3
    /// How big a file's icon is while it's dragged, and how far apart several are.
    static let iconSize: CGFloat = 32
    static let spread: CGFloat = 6

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        dragging = false
        if event.clickCount >= 2 {
            downAt = nil
            onDoubleClick?()
        } else {
            downAt = event.locationInWindow
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, !dragging else { return }
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) >= FileDragView.threshold else { return }
        let files = FileDragView.draggable(urls())
        guard !files.isEmpty else { return }
        dragging = true
        downAt = nil
        let grabbed = convert(start, from: nil)
        let items = files.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = FileDragView.iconSize
            icon.size = NSSize(width: size, height: size)
            let offset = CGFloat(min(index, 4)) * FileDragView.spread
            item.setDraggingFrame(NSRect(x: grabbed.x - size / 2 + offset, y: grabbed.y - size / 2 + offset, width: size, height: size),
                                  contents: icon)
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = files.count > 1 ? .stack : .none
        onStart?()
    }

    override func mouseUp(with event: NSEvent) {
        let clicked = downAt != nil && !dragging
        downAt = nil
        if clicked {
            onClick?()
        }
    }

    /// Taken away in the middle of a drag: whoever was told it started is told it's over.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil && dragging {
            dragging = false
            onEnd?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    /// The files that can be dragged: ones that are still there.
    static func draggable(_ urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: NSDraggingSource

    /// Wherever they're dropped, the files are copied (or attached): never moved away.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        onEnd?()
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}
