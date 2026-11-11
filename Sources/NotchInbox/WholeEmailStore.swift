import Foundation

/// Whole emails on disk, one file each, in ~/Library/Application Support/Notch Inbox/Emails,
/// in files only you can read. This is what lets an email from months ago open in full, even
/// offline. The newest ones are kept, up to the limit in Settings. They never leave this Mac.
final class WholeEmailStore {
    static var defaultFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Emails", isDirectory: true)
    }

    static let fileExtension = "email"
    /// How many whole emails to keep unless Settings says otherwise.
    static let standardLimit = 2000
    /// The choices in Settings; 0 means all of them.
    static let limits = [500, 2000, 10_000, 0]

    private let folder: URL
    /// Writing and tidying happen here, off the main thread, one at a time.
    private let queue = DispatchQueue(label: "NotchInbox.WholeEmails", qos: .utility)
    private let lock = NSLock()
    private var saved: Set<String> = []

    init(folder: URL = WholeEmailStore.defaultFolder) {
        self.folder = folder
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        saved = Set(names.compactMap { WholeEmailStore.id(fromFileName: $0) })
    }

    /// The emails that are on disk.
    var ids: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return saved
    }

    // MARK: Reading and writing

    /// Reads one email back. Nil if it isn't there or can't be read.
    func load(_ id: String) -> LiveMailbox.WholeEmail? {
        guard let data = try? Data(contentsOf: url(for: id)), let json = WholeEmailStore.unpack(data) else { return nil }
        return try? JSONDecoder().decode(LiveMailbox.WholeEmail.self, from: json)
    }

    /// Saves one email, shortly (not on the main thread).
    func save(_ email: LiveMailbox.WholeEmail, for id: String) {
        lock.lock()
        saved.insert(id)
        lock.unlock()
        let target = url(for: id)
        let folder = self.folder
        queue.async { [weak self] in
            guard let json = try? JSONEncoder().encode(email) else { return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try WholeEmailStore.pack(json).write(to: target, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            } catch {
                self?.forget(id)
            }
        }
    }

    private func forget(_ id: String) {
        lock.lock()
        saved.remove(id)
        lock.unlock()
    }

    /// Keeps the first `limit` of these emails (newest first) and deletes the rest, along
    /// with any that aren't on the list at all. A limit of 0 keeps every email on the list.
    func keep(_ newestFirst: [String], limit: Int) {
        let onDisk = ids
        var wanted = Set<String>()
        for id in newestFirst where onDisk.contains(id) {
            if limit > 0 && wanted.count >= limit { break }
            wanted.insert(id)
        }
        let extra = onDisk.subtracting(wanted)
        guard !extra.isEmpty else { return }
        lock.lock()
        saved.subtract(extra)
        lock.unlock()
        let targets = extra.map { url(for: $0) }
        queue.async {
            for target in targets {
                try? FileManager.default.removeItem(at: target)
            }
        }
    }

    /// How many emails are on disk and how much room they take, worked out off the main thread.
    func measure(_ done: @escaping (_ count: Int, _ bytes: Int) -> Void) {
        let folder = self.folder
        queue.async {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            var count = 0
            var bytes = 0
            for name in names where WholeEmailStore.id(fromFileName: name) != nil {
                count += 1
                let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
                bytes += (attributes?[.size] as? NSNumber)?.intValue ?? 0
            }
            let total = (count: count, bytes: bytes)
            DispatchQueue.main.async {
                done(total.count, total.bytes)
            }
        }
    }

    /// Waits for anything still being written (before quitting, and in checks).
    func finishWriting() {
        queue.sync {}
    }

    // MARK: Files

    private func url(for id: String) -> URL {
        folder.appendingPathComponent(WholeEmailStore.fileName(for: id))
    }

    /// "tag:gmail.google.com,2004:123" → "tag%3Agmail%2Egoogle%2Ecom%2C2004%3A123.email".
    static func fileName(for id: String) -> String {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return (safe.isEmpty ? "unnamed" : String(safe.prefix(200))) + "." + fileExtension
    }

    static func id(fromFileName name: String) -> String? {
        let suffix = "." + fileExtension
        guard name.hasSuffix(suffix), !name.hasPrefix(".") else { return nil }
        return String(name.dropLast(suffix.count)).removingPercentEncoding
    }

    // MARK: Packing

    private static let compressedMark = Data("NIZ1".utf8)
    private static let plainMark = Data("NIJ1".utf8)

    /// Emails are mostly HTML, which squeezes to a fraction of its size.
    static func pack(_ json: Data) -> Data {
        #if canImport(Darwin)
        if let squeezed = try? (json as NSData).compressed(using: .lzfse) as Data, squeezed.count < json.count {
            return compressedMark + squeezed
        }
        #endif
        return plainMark + json
    }

    static func unpack(_ data: Data) -> Data? {
        guard data.count >= 4 else { return nil }
        let mark = data.prefix(4)
        let rest = data.dropFirst(4)
        if mark == plainMark {
            return Data(rest)
        }
        #if canImport(Darwin)
        if mark == compressedMark {
            return try? (Data(rest) as NSData).decompressed(using: .lzfse) as Data
        }
        #endif
        return nil
    }
}
