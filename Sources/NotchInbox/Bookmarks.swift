import Foundation
#if canImport(Combine)
import Combine
#endif

/// A link you keep: its name, where it goes, and the group it's filed under (if any).
struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    /// A whole web address, starting https:// or http://.
    var url: String
    var group: String
    var added: Date

    init(id: UUID = UUID(), title: String, url: String, group: String = "", added: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.group = group
        self.added = Date(timeIntervalSince1970: added.timeIntervalSince1970.rounded(.down))
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, group, added
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try values.decode(String.self, forKey: .url)
        group = try values.decodeIfPresent(String.self, forKey: .group) ?? ""
        added = try values.decodeIfPresent(Date.self, forKey: .added) ?? Date(timeIntervalSince1970: 0)
    }

    /// The site it's on, e.g. "classroom.google.com".
    var site: String { BookmarkText.site(of: url) }
}

/// Reading what's typed, pasted or dropped as a bookmark.
enum BookmarkText {
    struct Parsed: Equatable {
        var title: String
        var url: String
    }

    /// A web address from one word: "classroom.google.com" becomes
    /// "https://classroom.google.com". Only web pages (http and https) count; nil if it
    /// isn't one.
    static func address(from word: String) -> String? {
        // Brackets, quotes and the punctuation of the sentence it sat in aren't part of it.
        var text = word.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()[],;!"))
        while text.hasSuffix(".") {
            text.removeLast()
        }
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }

        let lower = text.lowercased()
        var candidate = text
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            candidate = text
        } else if text.contains("://") || lower.hasPrefix("javascript:") || lower.hasPrefix("data:") || lower.hasPrefix("file:")
                    || lower.hasPrefix("mailto:") {
            return nil
        } else {
            candidate = "https://" + text
        }
        guard let parts = URLComponents(string: candidate), let scheme = parts.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = parts.host?.lowercased(), isSite(host) else { return nil }
        // A password in a link has no place in a bookmark.
        guard parts.user == nil, parts.password == nil else { return nil }
        return candidate
    }

    /// Whether a host looks like a real site: "example.com", "localhost", or numbers like
    /// "192.168.1.10".
    static func isSite(_ host: String) -> Bool {
        if host == "localhost" { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return false }
        if labels.allSatisfy({ $0.allSatisfy { $0.isNumber } }) {
            return labels.count == 4
        }
        guard let last = labels.last else { return false }
        return last.count >= 2 && last.allSatisfy { $0.isLetter }
    }

    /// The site a link is on, without "www.": "https://www.example.com/a" → "example.com".
    static func site(of address: String) -> String {
        guard let host = URLComponents(string: address)?.host?.lowercased() else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What was typed as a bookmark: a link by itself ("desmos.com"), or a name with its
    /// link before or after it ("Maths textbook https://…"). nil if there's no link in it.
    static func parse(_ typed: String) -> Parsed? {
        let words = typed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return nil }
        // The link is usually last or first; otherwise wherever it turns up.
        var places = Array(words.indices)
        if let last = places.popLast() {
            places.insert(last, at: 0)
        }
        for index in places {
            guard let url = address(from: words[index]) else { continue }
            var rest = words
            rest.remove(at: index)
            var title = rest.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "|-–—:·,"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Parsed(title: title.isEmpty ? site(of: url) : title, url: url)
        }
        return nil
    }

    /// The letter on a bookmark's badge.
    static func letter(for title: String) -> String {
        let first = title.first { $0.isLetter || $0.isNumber }
        return first.map { String($0).uppercased() } ?? "•"
    }

    /// A steady number from a site's name, so each site keeps its own colour.
    static func tint(for address: String) -> Int {
        var sum = 7
        for scalar in site(of: address).unicodeScalars {
            sum = (sum &* 31 &+ Int(scalar.value)) % 10_007
        }
        return sum
    }
}

/// Your bookmarks, in your order, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Bookmarks.json. They never leave this Mac.
final class BookmarksStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Bookmarks.json")
    }

    init(url: URL = BookmarksStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode([Bookmark].self, from: data) {
            bookmarks = saved.filter { BookmarkText.address(from: $0.url) != nil }
        }
    }

    func bookmark(_ id: UUID?) -> Bookmark? {
        guard let id = id else { return nil }
        return bookmarks.first { $0.id == id }
    }

    /// The groups in use, in the order they first appear.
    var groups: [String] {
        var seen: [String] = []
        for bookmark in bookmarks {
            let group = bookmark.group.trimmingCharacters(in: .whitespacesAndNewlines)
            if !group.isEmpty && !seen.contains(where: { $0.caseInsensitiveCompare(group) == .orderedSame }) {
                seen.append(group)
            }
        }
        return seen
    }

    /// The bookmarks in a group, or all of them for nil.
    func bookmarks(in group: String?) -> [Bookmark] {
        guard let group = group else { return bookmarks }
        return bookmarks.filter { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(group) == .orderedSame }
    }

    /// Adds a link. One you already have isn't added twice: you get the one that's there.
    /// nil if it isn't a web address.
    @discardableResult
    func add(title: String, url typed: String, group: String = "", now: Date = Date()) -> Bookmark? {
        guard let address = BookmarkText.address(from: typed) else { return nil }
        if let existing = bookmarks.first(where: { BookmarksStore.same($0.url, address) }) {
            return existing
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = Bookmark(title: name.isEmpty ? BookmarkText.site(of: address) : name, url: address,
                                group: group.trimmingCharacters(in: .whitespacesAndNewlines), added: now)
        bookmarks.append(bookmark)
        saveSoon()
        return bookmark
    }

    /// Adds what was typed or pasted: a link, or a name and a link.
    @discardableResult
    func add(typed: String, group: String = "", now: Date = Date()) -> Bookmark? {
        guard let parsed = BookmarkText.parse(typed) else { return nil }
        return add(title: parsed.title, url: parsed.url, group: group, now: now)
    }

    /// Two addresses that go to the same place: the same but for letter case in the site, a
    /// trailing slash, or "www.".
    static func same(_ first: String, _ second: String) -> Bool {
        func key(_ address: String) -> String {
            guard var parts = URLComponents(string: address) else { return address }
            parts.scheme = "https"
            var host = parts.host?.lowercased() ?? ""
            if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
            parts.host = host
            if parts.path == "/" { parts.path = "" }
            return parts.string ?? address
        }
        return key(first) == key(second)
    }

    /// Saves an edited bookmark. A name left blank becomes its site; a link that isn't a
    /// web address keeps the old one.
    func update(_ edited: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == edited.id }) else { return }
        var bookmark = edited
        bookmark.url = BookmarkText.address(from: edited.url) ?? bookmarks[index].url
        guard bookmark != bookmarks[index] else { return }
        bookmarks[index] = bookmark
        saveSoon()
    }

    /// Fills in a name that was left blank, once you've finished editing.
    func tidy(_ id: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        var bookmark = bookmarks[index]
        bookmark.title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmark.group = bookmark.group.trimmingCharacters(in: .whitespacesAndNewlines)
        if bookmark.title.isEmpty {
            bookmark.title = bookmark.site
        }
        guard bookmark != bookmarks[index] else { return }
        bookmarks[index] = bookmark
        saveSoon()
    }

    func remove(_ id: UUID) {
        let before = bookmarks.count
        bookmarks.removeAll { $0.id == id }
        if bookmarks.count != before {
            saveSoon()
        }
    }

    /// Whether a bookmark can move one place earlier (-1) or later (1) among the ones
    /// showing (a group's, or all of them).
    func canMove(_ id: UUID, by offset: Int, in group: String? = nil) -> Bool {
        let list = bookmarks(in: group)
        guard offset != 0, let index = list.firstIndex(where: { $0.id == id }) else { return false }
        return list.indices.contains(index + offset)
    }

    /// Moves a bookmark one place, swapping with its neighbour in the list that's showing.
    func move(_ id: UUID, by offset: Int, in group: String? = nil) {
        let list = bookmarks(in: group)
        guard offset != 0, let index = list.firstIndex(where: { $0.id == id }), list.indices.contains(index + offset),
              let from = bookmarks.firstIndex(where: { $0.id == id }),
              let to = bookmarks.firstIndex(where: { $0.id == list[index + offset].id }) else { return }
        bookmarks.swapAt(from, to)
        saveSoon()
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Writes the bookmarks to disk straight away (also on quit).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bookmarks) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save bookmarks: \(error.localizedDescription)")
        }
    }
}
