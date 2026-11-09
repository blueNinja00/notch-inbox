import Foundation

/// The little bit of HTTP the browser link needs: one small request per connection.
struct HTTPRequest {
    /// Whole HTML emails can run to a few megabytes.
    static let maxSize = 8 * 1024 * 1024

    let method: String
    let path: String
    /// Header names are lowercased.
    let headers: [String: String]
    let body: Data

    enum Parse {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    static func parse(_ data: Data) -> Parse {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .invalid
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxSize else { return .invalid }
        let bodyStart = end.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))

        return .complete(HTTPRequest(method: String(requestLine[0]),
                                     path: String(requestLine[1]),
                                     headers: headers,
                                     body: body))
    }

    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }
}

/// The "Notch Inbox Link" browser add-on and how the app recognises it.
enum LinkAddOn {
    /// Fixed ID, derived from the public key in BrowserExtension/manifest.json.
    static let id = "hhjiihfliaidbbicblcafpaikelnbdpp"
    static let port: UInt16 = 47823

    /// Only uploads made by the add-on itself are accepted.
    static func accepts(_ request: HTTPRequest) -> Bool {
        guard let origin = request.headers["origin"] else { return false }
        return origin.hasSuffix("://\(id)")
    }
}

/// What the add-on posts every minute: the unread-mail feeds of each signed-in account.
struct FeedUpload: Decodable {
    struct Feed: Decodable {
        let index: Int
        /// The Primary tab's feed (or the whole inbox when the account has no tabs).
        let xml: String
        /// The whole inbox, sent with the Primary feed so mail from Google itself
        /// (Classroom, Docs, Drive…) still shows when Gmail files it under Updates.
        /// Add-on 1.1 and later.
        let extra: String?
        /// Whether `xml` is the Primary tab (false: Gmail had no Primary feed, so it's the
        /// whole inbox). Add-on 1.3 and later.
        let primary: Bool?
    }

    let feeds: [Feed]
    /// The add-on's version; missing from add-on 1.0.
    let version: String?
    /// Whether the add-on fetches whole emails: "ok", "on-open" (only ones you open in
    /// the notch, because Gmail counts them as read) or "unknown" (still finding out).
    let fullEmails: String?
    /// The add-on's recent steps marking emails read in Gmail, for Copy Debug Info.
    /// Add-on 1.9 and later.
    let log: [String]?
}

extension FeedUpload.Feed {
    func parsed() -> AccountFeeds? {
        guard let main = GmailFeedParser.parse(Data(xml.utf8)) else { return nil }
        let inbox = extra.flatMap { GmailFeedParser.parse(Data($0.utf8)) }
        return AccountFeeds(main: main, inbox: inbox)
    }
}

/// The app's answer to a feed upload: the whole emails it would like next, and the
/// version of the add-on that came with the app, so an outdated add-on reloads itself.
struct LinkReply: Encodable, Equatable {
    struct Wanted: Encodable, Equatable {
        let account: String
        let id: String
        let link: String?
        let unread: Bool
        let opened: Bool
    }

    var want: [Wanted] = []
    var addon: String? = nil
    /// Emails you read in the notch, for the add-on to mark read in Gmail.
    var read: [Wanted] = []
    /// Whether the add-on may open a background tab when marking read out of sight fails
    /// (Settings → Gmail link). Off unless you turn it on.
    var tabs = false
}

/// One whole email from the add-on: its HTML and/or plain text, or why it couldn't be read.
struct EmailUpload: Decodable {
    let account: String
    let id: String
    let html: String?
    let text: String?
    let attachments: [String]?
    let error: String?
}
