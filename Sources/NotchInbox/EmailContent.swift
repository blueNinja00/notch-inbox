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
