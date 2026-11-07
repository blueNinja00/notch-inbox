import Foundation
#if canImport(Combine)
import Combine
#endif

/// Everything the notch UI renders from. Starts with sample mail; once the browser
/// add-on delivers real Gmail, `showLive` swaps it in.
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

    /// True until real mail arrives from the browser link.
    @Published private(set) var isSample = true
    /// Gmail's own unread counts per account (the feed lists only the newest ~20).
    @Published private(set) var reportedUnread: [String: Int] = [:]

    /// A newer build that's ready to install, if any. Shows as an Update button in the notch.
    @Published var pendingUpdate: Int? = nil
    var onInstallUpdate: (() -> Void)?
    /// Opens a link in the browser (set by the app).
    var onOpenURL: ((URL) -> Void)?

    init(provider: MailProvider, metrics: NotchMetrics) {
        let accounts = provider.accounts()
        self.accounts = accounts
        self.messages = provider.messages()
        self.metrics = metrics
        self.activeAccountID = accounts.first?.id ?? ""
    }

    /// Real Gmail arrives read-only: archive, mark unread and reply happen in Gmail.
    var canAct: Bool { isSample }

    /// Swap in real accounts and mail from the browser link.
    func showLive(accounts: [MailAccount], messages: [MailMessage], unread: [String: Int]) {
        let wasSample = isSample
        self.accounts = accounts
        self.messages = messages
        reportedUnread = unread
        isSample = false

        if wasSample || !accounts.contains(where: { $0.id == activeAccountID }) {
            activeAccountID = accounts.first?.id ?? ""
            openMessageID = nil
            replyFromID = nil
            sentFrom = nil
        }
        if let id = openMessageID, !messages.contains(where: { $0.id == id }) {
            openMessageID = nil
        }
        if accounts.isEmpty, level == .detail {
            level = .lanes
        }
    }

    // MARK: Reading

    /// Messages in one inbox, newest first.
    func inbox(_ accountID: String) -> [MailMessage] {
        messages.filter { $0.accountID == accountID }.sorted { $0.date > $1.date }
    }

    func unreadCount(_ accountID: String) -> Int {
        if let reported = reportedUnread[accountID] {
            return reported
        }
        return messages.filter { $0.accountID == accountID && $0.isUnread }.count
    }

    var totalUnread: Int {
        accounts.reduce(0) { $0 + unreadCount($1.id) }
    }

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

    /// Expand one inbox, opening the given message (or the newest).
    func open(accountID: String, messageID: String? = nil) {
        let target = messageID ?? inbox(accountID).first?.id
        activeAccountID = accountID
        openMessageID = target
        replyFromID = nil
        replyText = ""
        sentFrom = nil
        // Sample mail is marked read here; real mail is read when you open it in Gmail.
        if canAct, let target = target {
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
        guard canAct, let id = openMessageID else { return }
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
        guard canAct, let id = openMessageID else { return }
        setRead(id, false)
    }

    func chooseReplyAccount(_ id: String) {
        replyFromID = id
    }

    func send() {
        guard canAct, openMessage != nil else { return }
        // Sample data: nothing leaves the Mac. Real replies happen in Gmail.
        sentFrom = replyFrom?.name ?? "your account"
        replyText = ""
    }

    func installUpdate() {
        onInstallUpdate?()
    }

    // MARK: Gmail in the browser

    func openInGmail() {
        if let link = openMessage?.link {
            onOpenURL?(link)
        } else {
            openAccountInGmail(activeAccountID)
        }
    }

    func openAccountInGmail(_ accountID: String) {
        if let url = gmailURL(for: accountID) {
            onOpenURL?(url)
        }
    }

    /// New message in Gmail, from the inbox that's open (or the first account).
    func composeInGmail() {
        let accountID = level == .detail ? activeAccountID : (accounts.first?.id ?? activeAccountID)
        let compose = [URLQueryItem(name: "view", value: "cm"),
                       URLQueryItem(name: "fs", value: "1"),
                       URLQueryItem(name: "tf", value: "1")]
        if let url = gmailURL(for: accountID, extra: compose) {
            onOpenURL?(url)
        }
    }

    func gmailURL(for accountID: String, extra: [URLQueryItem] = []) -> URL? {
        guard let email = account(accountID)?.email else { return nil }
        var components = URLComponents(string: "https://mail.google.com/mail/u/")
        components?.queryItems = [URLQueryItem(name: "authuser", value: email)] + extra
        return components?.url
    }

    private func setRead(_ id: String, _ read: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isUnread = !read
    }
}
