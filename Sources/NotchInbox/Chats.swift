import Foundation
#if canImport(Combine)
import Combine
#endif

/// One message in a chat with the assistant: yours, or its answer.
struct ChatMessage: Identifiable, Equatable, Codable {
    typealias Role = ChatTurn.Role

    var id = UUID()
    let role: Role
    /// As streamed; shown without any <think> reasoning.
    var raw: String
    var failed = false
    /// Text from one of your documents that went with this question.
    var attachment: DocumentSelection?

    init(role: Role, raw: String, failed: Bool = false, attachment: DocumentSelection? = nil) {
        self.role = role
        self.raw = raw
        self.failed = failed
        self.attachment = attachment
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, raw, failed, attachment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try values.decode(Role.self, forKey: .role)
        raw = try values.decodeIfPresent(String.self, forKey: .raw) ?? ""
        failed = try values.decodeIfPresent(Bool.self, forKey: .failed) ?? false
        attachment = try? values.decodeIfPresent(DocumentSelection.self, forKey: .attachment)
    }

    /// Without reasoning or a block asking for a change (the app makes those).
    var text: String {
        role == .assistant ? AgentBlock.hidden(AssistantPrompt.withoutThinking(raw)) : raw
    }

    /// What the assistant is sent: your question, with any text you attached.
    var sent: String {
        attachment.map { DocumentText.attached(text, $0) } ?? text
    }
}

/// One conversation with the assistant.
struct Chat: Identifiable, Equatable, Codable {
    var id = UUID()
    /// A name you gave it. Without one, it's named after its first question.
    var title = ""
    var created: Date
    /// When something was last said in it.
    var updated: Date
    var messages: [ChatMessage] = []

    init(now: Date) {
        created = now
        updated = now
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, created, updated, messages
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        created = try values.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        updated = try values.decodeIfPresent(Date.self, forKey: .updated) ?? created
        messages = try values.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }

    var isEmpty: Bool { messages.isEmpty }

    /// What the list calls it: your name for it, its first question, or "New chat".
    var name: String {
        let own = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        guard let first = messages.first(where: { $0.role == .user })?.raw else { return "New chat" }
        let line = AgentStream.shorten(first, to: 44)
        return line.isEmpty ? "New chat" : line
    }

    /// The start of the latest answer, for under its name.
    var preview: String {
        guard let last = messages.last(where: { $0.role == .assistant && !$0.failed }) else { return "" }
        return AgentStream.shorten(AgentReport.plain(last.text), to: 60)
    }
}

/// Every chat with the assistant, and which one is open. They're kept on this Mac so they
/// carry over from one launch, and one update, to the next.
struct ChatBook: Equatable, Codable {
    private(set) var chats: [Chat] = []
    private(set) var currentID: UUID?

    /// How many chats are kept, and how many messages of each.
    static let mostChats = 30
    static let mostMessages = 200

    private enum CodingKeys: String, CodingKey {
        case chats, currentID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        chats = try values.decodeIfPresent([Chat].self, forKey: .chats) ?? []
        currentID = try values.decodeIfPresent(UUID.self, forKey: .currentID)
    }

    func chat(_ id: UUID?) -> Chat? {
        guard let id = id else { return nil }
        return chats.first { $0.id == id }
    }

    /// The chat that's open, if the book has been settled.
    var current: Chat? { chat(currentID) }

    /// For the list: a new, empty chat first, then the rest with the latest on top.
    var newestFirst: [Chat] {
        chats.sorted { one, other in
            if one.isEmpty != other.isEmpty { return one.isEmpty }
            if one.updated != other.updated { return one.updated > other.updated }
            return one.created > other.created
        }
    }

    /// Makes the book fit to use after it's read from disk: an answer cut off when the app
    /// quit is dropped, spare empty chats go, and there's always a chat open.
    mutating func settle(now: Date) {
        for index in chats.indices {
            while let last = chats[index].messages.last, last.role == .assistant,
                  last.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chats[index].messages.removeLast()
            }
        }
        if chat(currentID) == nil {
            currentID = newestFirst.first?.id
        }
        chats.removeAll { $0.isEmpty && $0.id != currentID }
        if chat(currentID) == nil {
            let fresh = Chat(now: now)
            chats.append(fresh)
            currentID = fresh.id
        }
        trim()
    }

    /// Opens a new, empty chat. If there's an empty one already, that's the one.
    @discardableResult
    mutating func startNew(now: Date) -> UUID {
        if let open = current, open.isEmpty { return open.id }
        if let spare = chats.first(where: { $0.isEmpty }) {
            currentID = spare.id
            return spare.id
        }
        let fresh = Chat(now: now)
        chats.append(fresh)
        currentID = fresh.id
        trim()
        return fresh.id
    }

    /// Opens a chat. An empty one left behind is cleared away.
    @discardableResult
    mutating func select(_ id: UUID) -> Bool {
        guard chat(id) != nil else { return false }
        guard id != currentID else { return true }
        let left = currentID
        currentID = id
        chats.removeAll { $0.isEmpty && $0.id == left }
        return true
    }

    /// Deletes a chat. If it was the open one, the latest of the others opens (or a new one).
    mutating func remove(_ id: UUID, now: Date) {
        guard chat(id) != nil else { return }
        chats.removeAll { $0.id == id }
        if currentID == id {
            currentID = nil
        }
        settle(now: now)
    }

    mutating func rename(_ id: UUID, to title: String) {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[index].title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    }

    /// Keeps what's been said in the open chat.
    mutating func setMessages(_ messages: [ChatMessage], now: Date) {
        guard let index = chats.firstIndex(where: { $0.id == currentID }) else { return }
        let kept = Array(messages.suffix(ChatBook.mostMessages))
        guard chats[index].messages != kept else { return }
        chats[index].messages = kept
        if !kept.isEmpty {
            chats[index].updated = now
        }
    }

    /// Deletes every chat and opens a new one.
    mutating func clear(now: Date) {
        chats = []
        currentID = nil
        settle(now: now)
    }

    /// Lets the oldest chats go once there are too many (never the open one).
    private mutating func trim() {
        guard chats.count > ChatBook.mostChats else { return }
        let keep = Set(newestFirst.filter { $0.id != currentID }.prefix(ChatBook.mostChats - 1).map { $0.id })
        chats.removeAll { $0.id != currentID && !keep.contains($0.id) }
    }
}

/// The chats, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Chats.json.
final class ChatsStore: ObservableObject {
    @Published private(set) var book: ChatBook

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Chats.json")
    }

    init(url: URL = ChatsStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var loaded = ChatBook()
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode(ChatBook.self, from: data) {
            loaded = saved
        }
        loaded.settle(now: Date())
        book = loaded
    }

    /// Changes the chats and saves them shortly after.
    func change(_ edit: (inout ChatBook) -> Void) {
        var changed = book
        edit(&changed)
        guard changed != book else { return }
        book = changed
        saveSoon()
    }

    private func saveSoon() {
        guard pendingSave == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Writes the chats to disk straight away (also on quit).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(book) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save chats: \(error.localizedDescription)")
        }
    }
}
