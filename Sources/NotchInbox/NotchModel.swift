import Foundation
#if canImport(Combine)
import Combine
#endif

/// Everything the notch UI renders from. Views call the intent methods below;
/// a real mail provider will later back `accounts` and `messages`.
final class NotchModel: ObservableObject {
    @Published var level: NotchLevel = .rest
    @Published var metrics: NotchMetrics
    @Published private(set) var accounts: [MailAccount]
    @Published private(set) var messages: [MailMessage]
    @Published private(set) var activeAccountID: String
    @Published private(set) var openMessageID: String?
    @Published private(set) var replyFromID: String?
    @Published var replyText: String = ""
    @Published private(set) var sentFrom: String?

    /// A newer build that's ready to install, if any. Shows as an Update button in the notch.
    @Published var pendingUpdate: Int? = nil
    var onInstallUpdate: (() -> Void)?

    init(provider: MailProvider, metrics: NotchMetrics) {
        let accounts = provider.accounts()
        self.accounts = accounts
        self.messages = provider.messages()
        self.metrics = metrics
        self.activeAccountID = accounts.first?.id ?? ""
    }

    // MARK: Reading

    /// Messages in one inbox, newest first.
    func inbox(_ accountID: String) -> [MailMessage] {
        messages.filter { $0.accountID == accountID }.sorted { $0.date > $1.date }
    }

    func unreadCount(_ accountID: String) -> Int {
        messages.filter { $0.accountID == accountID && $0.isUnread }.count
    }

    var totalUnread: Int { messages.filter { $0.isUnread }.count }

    func account(_ id: String) -> MailAccount? {
        accounts.first { $0.id == id }
    }

    var activeAccount: MailAccount? { account(activeAccountID) }

    var openMessage: MailMessage? {
        guard let id = openMessageID else { return nil }
        return messages.first { $0.id == id }
    }

    /// The account a reply goes out from: the inbox the mail arrived in, unless you pick another.
    var replyFrom: MailAccount? { account(replyFromID ?? activeAccountID) }

    /// What the hover tiles show: the newest unread message, or else the newest message.
    func headline(_ accountID: String) -> MailMessage? {
        let list = inbox(accountID)
        return list.first { $0.isUnread } ?? list.first
    }

    // MARK: Moving between levels

    func peek() {
        if level == .rest { level = .peek }
    }

    func unpeek() {
        if level == .peek { level = .rest }
    }

    func openLanes() {
        level = .lanes
    }

    func back() {
        level = .lanes
    }

    func close() {
        level = .rest
        sentFrom = nil
    }

    /// Expand one inbox, opening the given message (or the newest) and marking it read.
    func open(accountID: String, messageID: String? = nil) {
        let target = messageID ?? inbox(accountID).first?.id
        activeAccountID = accountID
        openMessageID = target
        replyFromID = nil
        replyText = ""
        sentFrom = nil
        if let target = target {
            setRead(target, true)
        }
        level = .detail
    }

    func open(accountAt index: Int) {
        guard accounts.indices.contains(index) else { return }
        open(accountID: accounts[index].id)
    }

    // MARK: Message actions

    /// Archive the open message and move on to the next one in the same inbox.
    func archiveOpen() {
        guard let id = openMessageID else { return }
        let before = inbox(activeAccountID)
        guard let index = before.firstIndex(where: { $0.id == id }) else { return }

        messages.removeAll { $0.id == id }

        let after = inbox(activeAccountID)
        let next: MailMessage? = after.isEmpty ? nil : after[min(index, after.count - 1)]
        openMessageID = next?.id
        if let next = next {
            setRead(next.id, true)
        }
        replyFromID = nil
        replyText = ""
        sentFrom = nil
    }

    func markOpenUnread() {
        guard let id = openMessageID else { return }
        setRead(id, false)
    }

    func chooseReplyAccount(_ id: String) {
        replyFromID = id
    }

    func send() {
        guard openMessage != nil else { return }
        // Sample data: nothing leaves the Mac yet. A real provider sends the reply here.
        sentFrom = replyFrom?.name ?? "your account"
        replyText = ""
    }

    func installUpdate() {
        onInstallUpdate?()
    }

    private func setRead(_ id: String, _ read: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isUnread = !read
    }
}
