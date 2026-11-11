import Foundation
#if canImport(Combine)
import Combine
#endif

/// A file parked on the shelf: a pointer to where it is, not a copy.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let added: Date

    var name: String { url.lastPathComponent }
}

/// The shelf: drop files on the notch to park them, then drag them out wherever they're
/// going. It keeps pointers to the files (nothing is copied or moved), newest first.
struct ShelfList: Equatable {
    static let limit = 40

    private(set) var items: [ShelfItem] = []

    /// Adds files, newest first. One that's already there moves to the front. Returns how
    /// many were new.
    @discardableResult
    mutating func add(_ urls: [URL], now: Date = Date()) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            if let index = items.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                items.insert(items.remove(at: index), at: 0)
            } else {
                items.insert(ShelfItem(id: UUID(), url: url.standardizedFileURL, added: now), at: 0)
                added += 1
            }
        }
        if items.count > ShelfList.limit {
            items.removeLast(items.count - ShelfList.limit)
        }
        return added
    }

    mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func clear() {
        items = []
    }

    /// Forgets files that have been moved or deleted since. Returns whether any went.
    @discardableResult
    mutating func prune(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> Bool {
        let before = items.count
        items.removeAll { !exists($0.url) }
        return items.count != before
    }

    /// Where the files are, to remember between launches.
    var paths: [String] { items.map { $0.url.path } }

    init() {}

    /// The shelf as it was saved: first is newest.
    init(paths: [String], now: Date = Date()) {
        items = paths.prefix(ShelfList.limit).map { ShelfItem(id: UUID(), url: URL(fileURLWithPath: $0), added: now) }
    }
}

/// The shelf, shared by every screen's notch. Which files are on it is remembered between
/// launches (their paths, in this app's settings).
final class ShelfStore: ObservableObject {
    @Published private(set) var list: ShelfList

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "shelfFiles") {
        self.defaults = defaults
        self.key = key
        var saved = ShelfList(paths: defaults.stringArray(forKey: key) ?? [])
        saved.prune()
        list = saved
    }

    var items: [ShelfItem] { list.items }

    func add(_ urls: [URL]) {
        change { $0.add(urls) }
    }

    func remove(_ id: UUID) {
        change { $0.remove(id) }
    }

    func clear() {
        change { $0.clear() }
    }

    /// Forgets files that are gone (called when the shelf is shown).
    func prune() {
        change { $0.prune() }
    }

    private func change(_ edit: (inout ShelfList) -> Void) {
        var changed = list
        edit(&changed)
        guard changed != list else { return }
        list = changed
        defaults.set(changed.paths, forKey: key)
    }
}
