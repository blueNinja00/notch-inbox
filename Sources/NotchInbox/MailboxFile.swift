import Foundation

/// Where the copy of the notch's mail is kept between launches: a file only you can read,
/// in ~/Library/Application Support/Notch Inbox. It never leaves this Mac.
enum MailboxFile {
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Mailbox.json")
    }

    static func load(from url: URL = defaultURL) -> LiveMailbox.Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(LiveMailbox.Snapshot.self, from: data)
    }

    static func encode(_ snapshot: LiveMailbox.Snapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    /// Writes the copy (only you can read it). Returns false if that failed.
    @discardableResult
    static func save(_ data: Data, to url: URL = defaultURL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
