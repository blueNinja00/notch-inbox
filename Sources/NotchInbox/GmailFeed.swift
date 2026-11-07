import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One account's unread-mail feed from Gmail, as passed on by the browser add-on.
struct GmailFeed: Equatable {
    struct Entry: Equatable {
        let id: String
        let subject: String
        let summary: String
        let link: URL?
        let date: Date
        let senderName: String
        let senderEmail: String
    }

    /// The signed-in address, lowercased.
    let account: String
    /// Gmail's exact unread count. The feed itself lists only about 20 messages.
    let unreadCount: Int
    let entries: [Entry]
}

/// Reads Gmail's Atom 0.3 feed (`/mail/u/N/feed/atom`).
final class GmailFeedParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> GmailFeed? {
        let delegate = GmailFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawFeed else { return nil }
        return delegate.makeFeed()
    }

    private var stack: [String] = []
    private var text = ""
    private var sawFeed = false
    private var feedTitle = ""
    private var fullCount = 0
    private var entries: [GmailFeed.Entry] = []
    private var fields: [String: String] = [:]
    private var link: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "feed" {
            sawFeed = true
        }
        if elementName == "entry" {
            fields = [:]
            link = nil
        }
        if elementName == "link", stack.last == "entry" {
            link = attributeDict["href"]
        }
        stack.append(elementName)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stack.isEmpty {
            stack.removeLast()
        }
        let parent = stack.last ?? ""

        switch (parent, elementName) {
        case ("feed", "title"):
            feedTitle = value
        case ("feed", "fullcount"):
            fullCount = Int(value) ?? 0
        case ("entry", "title"), ("entry", "summary"), ("entry", "issued"), ("entry", "modified"), ("entry", "id"):
            fields[elementName] = value
        case ("author", "name"):
            fields["name"] = value
        case ("author", "email"):
            fields["email"] = value
        case ("feed", "entry"):
            entries.append(makeEntry())
        default:
            break
        }
        text = ""
    }

    private func makeEntry() -> GmailFeed.Entry {
        let email = fields["email"] ?? ""
        let date = GmailFeedParser.date(from: fields["issued"])
            ?? GmailFeedParser.date(from: fields["modified"])
            ?? Date()
        return GmailFeed.Entry(id: nonEmpty(fields["id"]) ?? link ?? UUID().uuidString,
                               subject: nonEmpty(fields["title"]) ?? "(no subject)",
                               summary: fields["summary"] ?? "",
                               link: link.flatMap { URL(string: $0) },
                               date: date,
                               senderName: nonEmpty(fields["name"]) ?? nonEmpty(email) ?? "Unknown sender",
                               senderEmail: email)
    }

    private func makeFeed() -> GmailFeed? {
        // The feed title ends with the signed-in address; message links carry it too.
        let fromTitle = feedTitle.split(separator: " ").last(where: { $0.contains("@") }).map { String($0) }
        let fromLinks = entries.lazy.compactMap { GmailFeedParser.accountID(in: $0.link) }.first
        guard let account = fromTitle ?? fromLinks else { return nil }
        return GmailFeed(account: account.lowercased(),
                         unreadCount: max(fullCount, entries.count),
                         entries: entries)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    static func accountID(in url: URL?) -> String? {
        guard let url = url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first(where: { $0.name == "account_id" })?.value
    }

    private static let isoPlain = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        return isoPlain.date(from: string) ?? isoFractional.date(from: string)
    }
}

extension GmailFeed {
    /// This feed plus mail from Google itself (Classroom, Docs, Drive, Calendar…) found in
    /// the whole inbox, so school notices show even when Gmail files them under Updates.
    func addingGoogleMail(from inbox: GmailFeed) -> GmailFeed {
        guard inbox.account == account else { return self }
        let known = Set(entries.map { $0.id })
        let extras = inbox.entries.filter { !known.contains($0.id) && GmailFeed.isFromGoogle($0.senderEmail) }
        guard !extras.isEmpty else { return self }
        return GmailFeed(account: account,
                         unreadCount: unreadCount + extras.count,
                         entries: (entries + extras).sorted { $0.date > $1.date })
    }

    /// Sent from google.com or one of its subdomains, e.g. no-reply@classroom.google.com.
    static func isFromGoogle(_ address: String) -> Bool {
        guard let at = address.lastIndex(of: "@") else { return false }
        let domain = address[address.index(after: at)...].lowercased()
        return domain == "google.com" || domain.hasSuffix(".google.com")
    }
}

/// Which of an account's unread mail the notch shows.
enum InboxChoice: String, Codable {
    /// The Primary tab, plus Classroom and other mail from Google wherever Gmail filed it.
    case primary
    /// Everything unread in the inbox, every tab. Suits catch-all and receipts accounts.
    case everything
}

/// One account's feeds from the add-on: its Primary tab and (add-on 1.1 on) its whole inbox.
struct AccountFeeds: Equatable {
    /// The Primary tab, or the whole inbox for an account that has no Primary feed.
    let main: GmailFeed
    /// The whole inbox, when the add-on sent it as well.
    let inbox: GmailFeed?

    var account: String { main.account }

    /// The feed for the notch, as chosen for this account.
    func feed(showing choice: InboxChoice) -> GmailFeed {
        guard let inbox = inbox, inbox.account == main.account else { return main }
        switch choice {
        case .primary:
            return main.addingGoogleMail(from: inbox)
        case .everything:
            return inbox
        }
    }
}

extension InboxChoice {
    /// Where an account starts until you pick in the app menu: the whole inbox for an
    /// address that collects receipts and sign-ups (a catch-all, say), since Gmail files
    /// that mail outside Primary; the Primary tab plus Google mail for everyday accounts.
    static func starting(for address: String) -> InboxChoice {
        let local = address.split(separator: "@").first.map { $0.lowercased() } ?? ""
        if local.filter({ $0.isLetter }).contains("catchall") {
            return .everything
        }
        let words = Set(local.split(whereSeparator: { !$0.isLetter }).map { String($0) })
        return words.isDisjoint(with: collectorWords) ? .primary : .everything
    }

    private static let collectorWords: Set<String> = [
        "purchase", "purchases", "receipt", "receipts", "order", "orders", "shop", "shopping",
        "billing", "invoice", "invoices", "signup", "signups", "newsletter", "newsletters",
        "deals", "promo", "promos", "subscriptions", "spam", "junk",
    ]
}
