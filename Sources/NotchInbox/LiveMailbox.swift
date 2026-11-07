import Foundation

/// Turns Gmail feeds into the notch's accounts and messages. The feeds only list
/// unread mail, so a message that drops out was read in Gmail: it stays, greyed out.
struct LiveMailbox {
    static let maxAccounts = 3
    static let keepPerAccount = 40
    static let palette: [UInt32] = [0xF6C26B, 0x4C8DF6, 0x3FBF91]

    /// Account addresses in the order first seen, remembered between launches so
    /// each account keeps its lane and colour.
    private(set) var order: [String]
    private(set) var unread: [String: Int] = [:]
    private var store: [String: MailMessage] = [:]

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
    }

    /// Up to three accounts that have reported in, in their remembered order.
    var accounts: [MailAccount] {
        let active = order.filter { unread[$0] != nil }.prefix(LiveMailbox.maxAccounts)
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
        return store.values.filter { shown.contains($0.accountID) }
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
