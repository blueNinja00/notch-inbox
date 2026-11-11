import Foundation

/// Tidies whole emails from the browser add-on before the notch shows them.
enum EmailContent {
    /// Bigger HTML emails (in bytes) show Gmail's preview instead.
    static let maxHTMLBytes = 6 * 1024 * 1024
    static let maxParagraphs = 400

    /// The email's HTML without scripts, refresh redirects or <base> tags. The notch shows
    /// emails with JavaScript switched off anyway; this is a second lock on the door.
    static func cleanHTML(_ html: String) -> String? {
        guard html.utf8.count <= maxHTMLBytes else { return nil }
        var cleaned = html
        for pattern in removals {
            let whole = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = pattern.stringByReplacingMatches(in: cleaned, options: [], range: whole, withTemplate: "")
        }
        return cleaned.contains(where: { !$0.isWhitespace }) ? cleaned : nil
    }

    private static let removals: [NSRegularExpression] = [
        "<script\\b[^>]*>[\\s\\S]*?</script\\s*>",
        "<script\\b[^>]*>",
        "<meta\\b[^>]*http-equiv\\s*=\\s*[\"']?refresh[^>]*>",
        "<base\\b[^>]*>",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// An HTML email as plain text, for reading dates out of it: tags gone, a line break where
    /// a paragraph, row or line ended. Only the start of a very long email is read.
    static func text(fromHTML html: String, limit: Int = 300_000) -> String {
        var text = String(html.prefix(limit))
        for (pattern, replacement) in conversions {
            let whole = NSRange(text.startIndex..., in: text)
            text = pattern.stringByReplacingMatches(in: text, options: [], range: whole, withTemplate: replacement)
        }
        text = decodeEntities(text)
        let lines = text.components(separatedBy: "\n").map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00a0}" || $0 == "\u{202f}" || $0 == "\r" }).joined(separator: " ")
        }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    private static let conversions: [(NSRegularExpression, String)] = [
        ("<!--[\\s\\S]*?-->", ""),
        ("<(style|script|head|title)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", ""),
        ("\\s+", " "),
        ("<br\\b[^>]*>", "\n"),
        ("</(p|div|tr|li|h[1-6]|table|blockquote)\\s*>", "\n"),
        ("</(td|th)\\s*>", " "),
        ("<[^>]+>", ""),
    ].compactMap { pair in
        (try? NSRegularExpression(pattern: pair.0, options: [.caseInsensitive])).map { ($0, pair.1) }
    }

    private static let entities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "ndash": "–", "mdash": "—",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "middot": "·", "bull": "•",
    ]
    private static let entity = try? NSRegularExpression(pattern: "&(#[0-9]{1,7}|#x[0-9a-f]{1,6}|[a-z]{2,8});", options: [.caseInsensitive])

    /// "&amp;" → "&", "&#39;" → "'", "&#x2019;" → "’". Anything unknown is left as it is.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let entity = entity else { return text }
        var result = ""
        var position = text.startIndex
        for match in entity.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            result += text[position..<whole.lowerBound]
            let name = text[inner].lowercased()
            var decoded: String?
            if name.hasPrefix("#x") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else {
                decoded = entities[name]
            }
            result += decoded ?? String(text[whole])
            position = whole.upperBound
        }
        result += text[position...]
        return result
    }

    /// Plain text split into paragraphs at blank lines, keeping single line breaks.
    static func paragraphs(_ text: String) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            let trimmed = String(line.reversed().drop(while: { $0.isWhitespace }).reversed())
            if trimmed.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(trimmed)
            }
            if paragraphs.count >= maxParagraphs { break }
        }
        if !current.isEmpty, paragraphs.count < maxParagraphs {
            paragraphs.append(current.joined(separator: "\n"))
        }
        return paragraphs
    }
}
