import Foundation

/// Turns Gmail feeds into the notch's accounts and messages. The feeds only list
/// unread mail, so a message that drops out was read in Gmail: it stays, greyed out.
/// Whole emails arrive separately from the add-on and replace Gmail's short preview.
struct LiveMailbox {
    static let maxAccounts = 3
    static let keepPerAccount = 40
    static let palette: [UInt32] = [0xF6C26B, 0x4C8DF6, 0x3FBF91]
    /// Whole emails asked for per account at a time.
    static let wantPerAccount = 8
    /// How long to wait before asking again for a whole email the add-on couldn't fetch.
    static let retryAfter: TimeInterval = 30 * 60

    struct WholeEmail: Equatable {
        let html: String?
        let paragraphs: [String]
        let attachments: [String]
    }

    /// Account addresses in the order first seen, remembered between launches so
    /// each account keeps its lane and colour.
    private(set) var order: [String]
    private(set) var unread: [String: Int] = [:]
    private var store: [String: MailMessage] = [:]
    private var whole: [String: WholeEmail] = [:]
    /// When the add-on last failed to fetch a whole email.
    private var failed: [String: Date] = [:]
    /// Emails you opened in the notch: their whole text is fetched first.
    private var opened: Set<String> = []
    /// Accounts you chose to keep out of the notch.
    var hidden: Set<String> = []

    init(order: [String] = []) {
        self.order = order
    }

    mutating func apply(_ feeds: [GmailFeed]) {
        for feed in feeds {
            let account = feed.account
            if !order.contains(account) {
                order.append(account)
            }
            unread[account] = feed.unreadCount

            let stillUnread = Set(feed.entries.map { $0.id })
            for (id, message) in store where message.accountID == account && message.isUnread && !stillUnread.contains(id) {
                store[id]?.isUnread = false
            }
            for entry in feed.entries {
                store[entry.id] = MailMessage(id: entry.id,
                                              accountID: account,
                                              sender: entry.senderName,
                                              subject: entry.subject,
                                              body: entry.summary.isEmpty ? [] : [entry.summary],
                                              date: entry.date,
                                              isUnread: true,
                                              link: entry.link)
            }

            let newestFirst = store.values.filter { $0.accountID == account }.sorted { $0.date > $1.date }
            for stale in newestFirst.dropFirst(LiveMailbox.keepPerAccount) {
                store[stale.id] = nil
            }
        }
        // Whole emails and notes for messages that are gone.
        whole = whole.filter { store[$0.key] != nil }
        failed = failed.filter { store[$0.key] != nil }
        opened = opened.filter { store[$0] != nil }
    }

    /// Drops the mail the notch holds for one account (its lane stays), e.g. before showing
    /// a different part of its inbox, so mail from the old view isn't mistaken for mail
    /// read in Gmail.
    mutating func forget(_ account: String) {
        store = store.filter { $0.value.accountID != account }
    }

    /// Every account the browser reported, in their remembered order, shown or not.
    var linkedAccounts: [String] {
        order.filter { unread[$0] != nil }
    }

    /// Up to three accounts that have reported in and aren't hidden, in their remembered order.
    var accounts: [MailAccount] {
        let active = linkedAccounts.filter { !hidden.contains($0) }.prefix(LiveMailbox.maxAccounts)
        return active.enumerated().map { index, email in
            let name = LiveMailbox.label(for: email)
            return MailAccount(id: email,
                               name: name,
                               letter: String(name.prefix(1)).uppercased(),
                               colorHex: LiveMailbox.palette[index % LiveMailbox.palette.count],
                               shortcut: String(index + 1),
                               email: email)
        }
    }

    var messages: [MailMessage] {
        let shown = Set(accounts.map { $0.id })
        return store.values.filter { shown.contains($0.accountID) }.map { message in
            var message = message
            guard let email = whole[message.id] else {
                message.couldNotLoad = failed[message.id] != nil
                return message
            }
            message.html = email.html
            if !email.paragraphs.isEmpty {
                message.body = email.paragraphs
            }
            if let first = email.attachments.first {
                let more = email.attachments.count - 1
                message.attachment = more > 0 ? "\(first) and \(more) more" : first
            }
            message.isWhole = true
            return message
        }
    }

    // MARK: Whole emails

    /// Whole emails to ask the add-on for: ones you opened first, then the newest unread,
    /// taking turns between accounts. Ones that failed recently wait a while.
    func wanted(now: Date = Date()) -> [LinkReply.Wanted] {
        var perAccount: [[MailMessage]] = []
        for account in accounts {
            let candidates = store.values.filter { message in
                guard message.accountID == account.id, whole[message.id] == nil else { return false }
                guard message.isUnread || opened.contains(message.id) else { return false }
                guard let failedAt = failed[message.id] else { return true }
                return now.timeIntervalSince(failedAt) > LiveMailbox.retryAfter
            }
            let ordered = candidates.sorted { a, b in
                let aOpened = opened.contains(a.id)
                let bOpened = opened.contains(b.id)
                if aOpened != bOpened { return aOpened }
                if a.date != b.date { return a.date > b.date }
                return a.id < b.id
            }
            perAccount.append(Array(ordered.prefix(LiveMailbox.wantPerAccount)))
        }

        var picked: [LinkReply.Wanted] = []
        for rank in 0..<LiveMailbox.wantPerAccount {
            for messages in perAccount where rank < messages.count {
                let message = messages[rank]
                picked.append(LinkReply.Wanted(account: message.accountID,
                                               id: message.id,
                                               link: message.link?.absoluteString,
                                               unread: message.isUnread,
                                               opened: opened.contains(message.id)))
            }
        }
        return picked.filter { $0.opened } + picked.filter { !$0.opened }
    }

    /// Takes in a whole email from the add-on. Returns false if it's for a message the
    /// notch no longer has.
    @discardableResult
    mutating func storeWhole(_ upload: EmailUpload, now: Date = Date()) -> Bool {
        guard let message = store[upload.id], message.accountID == upload.account else { return false }
        let html = upload.html.flatMap { EmailContent.cleanHTML($0) }
        let paragraphs = upload.text.map { EmailContent.paragraphs($0) } ?? []
        guard html != nil || !paragraphs.isEmpty else {
            failed[upload.id] = now
            return true
        }
        whole[upload.id] = WholeEmail(html: html, paragraphs: paragraphs, attachments: upload.attachments ?? [])
        failed[upload.id] = nil
        return true
    }

    /// You opened this email in the notch: fetch its whole text next, even if it's read.
    mutating func markOpened(_ id: String) {
        guard store[id] != nil else { return }
        opened.insert(id)
        failed[id] = nil // looking at it is worth one more try
    }

    // MARK: Keeping a copy between launches

    /// What the notch held, so it can show your mail the moment the app starts (after an
    /// update, say) instead of waiting for the browser add-on. Whole emails aren't kept;
    /// the add-on fetches them again.
    struct Snapshot: Codable, Equatable {
        struct Message: Codable, Equatable {
            let id: String
            let accountID: String
            let sender: String
            let subject: String
            let preview: String
            let date: Date
            let isUnread: Bool
            let link: URL?
        }

        var savedAt: Date
        var order: [String]
        var unread: [String: Int]
        var messages: [Message]
        /// What each account was showing (Primary or whole inbox) when this was saved.
        var views: [String: InboxChoice]? = nil
    }

    func snapshot(at date: Date = Date()) -> Snapshot {
        let messages = store.values
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
            .map { message in
                Snapshot.Message(id: message.id, accountID: message.accountID, sender: message.sender,
                                 subject: message.subject, preview: message.body.first ?? "",
                                 date: message.date, isUnread: message.isUnread, link: message.link)
            }
        return Snapshot(savedAt: date, order: order, unread: unread, messages: messages)
    }

    init(snapshot: Snapshot) {
        order = snapshot.order
        unread = snapshot.unread
        for message in snapshot.messages {
            store[message.id] = MailMessage(id: message.id,
                                            accountID: message.accountID,
                                            sender: message.sender,
                                            subject: message.subject,
                                            body: message.preview.isEmpty ? [] : [message.preview],
                                            date: message.date,
                                            isUnread: message.isUnread,
                                            link: message.link)
        }
    }

    /// A short name for an address until the settings page lets you rename it:
    /// "you@gmail.com" → "you", "z123@ad.unsw.edu.au" → "UNSW", "me@acme-studio.com" → "Acme-studio".
    static func label(for email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map { String($0) }
        guard parts.count == 2, !parts[0].isEmpty else { return email }
        let local = parts[0]
        let domain = parts[1].lowercased()
        if domain == "gmail.com" || domain == "googlemail.com" {
            return local
        }
        let generic: Set<String> = ["com", "net", "org", "edu", "gov", "co", "ac", "au", "uk", "nz",
                                    "io", "me", "info", "biz", "mail", "email"]
        let meaningful = domain.split(separator: ".").map { String($0) }.filter { !generic.contains($0) }
        guard let name = meaningful.last, !name.isEmpty else { return local }
        return name.count <= 4 ? name.uppercased() : name.prefix(1).uppercased() + name.dropFirst()
    }
}
