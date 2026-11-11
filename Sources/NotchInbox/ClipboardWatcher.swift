import AppKit
import Combine

/// Keeps the last things you copied, so you can copy one again. It looks at the clipboard
/// about once a second. The list is held in memory only: it's never written to disk, never
/// sent anywhere, never shown to the assistant, and it's gone when the app quits. Copies
/// that password managers mark as private are skipped.
final class ClipboardWatcher: ObservableObject {
    static let shared = ClipboardWatcher()

    @Published private(set) var list = ClipList()

    private var timer: Timer?
    private var lastChange = 0
    /// The change the notch made itself, by copying a clip back.
    private var ownChange: Int?

    var isWatching: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // What's on the clipboard already isn't taken: only what you copy from now on.
        lastChange = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.look()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops watching and forgets everything.
    func stop() {
        timer?.invalidate()
        timer = nil
        clear()
    }

    private func look() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChange else { return }
        lastChange = count
        if ownChange == count { return }
        let types = (pasteboard.types ?? []).map { $0.rawValue }
        guard !ClipList.isPrivate(types: types), let text = pasteboard.string(forType: .string) else { return }
        var changed = list
        if changed.add(text) {
            list = changed
        }
    }

    /// Puts a clip back on the clipboard, ready to paste, and moves it to the top.
    func copy(_ clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(clip.text, forType: .string)
        ownChange = pasteboard.changeCount
        lastChange = pasteboard.changeCount
        var changed = list
        if changed.add(clip.text) {
            list = changed
        }
    }

    func remove(_ id: UUID) {
        var changed = list
        changed.remove(id)
        if changed != list {
            list = changed
        }
    }

    func clear() {
        if !list.clips.isEmpty {
            list = ClipList()
        }
    }
}
