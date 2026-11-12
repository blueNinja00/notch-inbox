import AppKit
import ApplicationServices

/// Types into the document you're working in, and reads what you've selected there.
///
/// It keeps track of the app you were last in (the notch never takes its place as the
/// front app). To type, it puts the text on the clipboard, presses ⌘V in that app, and
/// puts your clipboard back. To read a selection, it asks the app directly, and if the app
/// can't say, presses ⌘C and reads the clipboard. Pressing keys in another app is
/// something macOS only lets a trusted app do (Accessibility, in System Settings); without
/// that, the text is left on the clipboard for you to paste yourself.
final class DocumentTyper {
    /// The app you were last in, where typing goes.
    private(set) var target: NSRunningApplication?
    /// The target changed (its name, or nil).
    var onTargetChanged: ((String?) -> Void)?

    private var observer: NSObjectProtocol?

    /// Whether macOS lets this app press keys in others.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its "allow Notch Inbox to control this computer" prompt.
    static func askForAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Opens System Settings at Privacy & Security → Accessibility.
    static func openAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        guard observer == nil else { return }
        consider(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notice in
            self?.consider(notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private func consider(_ app: NSRunningApplication?) {
        guard let app = app, DocumentText.canTarget(bundleID: app.bundleIdentifier, own: Bundle.main.bundleIdentifier) else { return }
        guard app.processIdentifier != target?.processIdentifier else { return }
        target = app
        onTargetChanged?(targetName)
    }

    /// "Pages", "Google Chrome"…
    var targetName: String? {
        guard let target = target, !target.isTerminated else { return nil }
        return target.localizedName
    }

    // MARK: Typing

    /// Types `text` where the cursor is in the target app, replacing anything selected.
    /// `closeNotch` is called first, so the keys go to the app and not to the notch.
    func typeText(_ text: String, closeNotch: () -> Void, done: @escaping (DocumentText.Outcome) -> Void) {
        guard let app = target, !app.isTerminated else {
            done(.nowhere)
            return
        }
        let name = app.localizedName ?? ""
        let pasteboard = NSPasteboard.general
        guard DocumentTyper.isTrusted else {
            // Not allowed to press keys: leave it on the clipboard to paste by hand.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            done(.copied(app: name))
            return
        }
        let saved = SavedPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Marked as there only for a moment, so clipboard histories (this app's too) skip it.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        closeNotch()
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            DocumentTyper.press(9, with: .maskCommand) // ⌘V
            done(.typed(app: name))
            // Your own clipboard goes back once the app has taken the paste.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                saved.restore(to: pasteboard)
            }
        }
    }

    // MARK: Reading a selection

    /// What's selected in the target app, or nil if nothing is, or it can't be read.
    func selection(done: @escaping (String?) -> Void) {
        guard DocumentTyper.isTrusted, let app = target, !app.isTerminated else {
            done(nil)
            return
        }
        if let text = DocumentTyper.selectedText(in: app), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            done(text)
            return
        }
        // The app won't say (web pages and Google Docs don't): copy it, read it, and put
        // your clipboard back.
        let pasteboard = NSPasteboard.general
        let saved = SavedPasteboard(pasteboard)
        let before = pasteboard.changeCount
        DocumentTyper.press(8, with: .maskCommand, to: app.processIdentifier) // ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard pasteboard.changeCount != before else {
                done(nil)
                return
            }
            let copied = pasteboard.string(forType: .string)
            saved.restore(to: pasteboard)
            done(copied)
        }
    }

    /// Asks the app what's selected in the part of it that has the cursor.
    private static func selectedText(in app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let found = focused, CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        let field = unsafeBitCast(found, to: AXUIElement.self)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Presses a key with ⌘ held: in whichever app is in front, or in one app in particular.
    private static func press(_ key: CGKeyCode, with flags: CGEventFlags, to pid: pid_t? = nil) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            if let pid = pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
}

/// Everything on the clipboard, kept for a moment so it can be put back.
struct SavedPasteboard {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var kept: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    kept[type] = data
                }
            }
            return kept
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.filter { !$0.isEmpty }.map { kept -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in kept {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
