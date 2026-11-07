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
