import Foundation

/// How the assistant asks the app to change something: a block of JSON between tags at the
/// end of its answer, like <timetable>{…}</timetable>. The app makes the change and hides
/// the block, so you only see the answer in words.
enum AgentBlock {
    /// Every kind of block the assistant may use.
    static let tags = ["timetable", "planner"]

    /// The JSON inside the last <tag>…</tag> block, without any code fence around it.
    static func json(in text: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let open = text.range(of: openTag, options: .backwards),
              let close = text.range(of: closeTag, range: open.upperBound..<text.endIndex) else { return nil }
        var json = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Models sometimes wrap it in a code fence.
        if json.hasPrefix("```") {
            json = json.drop { $0 != "\n" }.trimmingCharacters(in: .whitespacesAndNewlines)
            if json.hasSuffix("```") { json = String(json.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return json
    }

    /// The answer without any change blocks, including one that's still streaming in.
    static func hidden(_ text: String, tags: [String] = AgentBlock.tags) -> String {
        var result = text
        for tag in tags {
            let openTag = "<\(tag)>"
            let closeTag = "</\(tag)>"
            while let open = result.range(of: openTag) {
                if let close = result.range(of: closeTag, range: open.upperBound..<result.endIndex) {
                    result.removeSubrange(open.lowerBound..<close.upperBound)
                } else {
                    result.removeSubrange(open.lowerBound..<result.endIndex) // still arriving
                }
            }
        }
        // A tag only partly arrived, like "<time".
        if let lastOpen = result.lastIndex(of: "<") {
            let tail = String(result[lastOpen...])
            if tags.contains(where: { "<\($0)>".hasPrefix(tail) }) {
                result.removeSubrange(lastOpen..<result.endIndex)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
