import Foundation

/// The little bit of HTTP the browser link needs: one small request per connection.
struct HTTPRequest {
    static let maxSize = 4 * 1024 * 1024

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

/// What the add-on posts: one raw feed per signed-in account.
struct FeedUpload: Decodable {
    struct Feed: Decodable {
        let index: Int
        let xml: String
    }

    let feeds: [Feed]
}
