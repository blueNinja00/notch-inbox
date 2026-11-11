import Foundation

/// Reads Google Classroom's notification emails, on this Mac: what was set, for which class,
/// and when it's due. New assignments and questions become homework in the planner; a
/// reminder fills in a due date; work a teacher returned is ticked off.
enum ClassroomMail {
    enum Kind: Equatable {
        /// Something to hand in.
        case assignment
        case question
        /// "Due tomorrow": a reminder about work not handed in yet.
        case reminder
        /// A teacher marked it or gave it back.
        case returned
        /// Announcements, materials, comments: nothing to hand in (as far as the email says).
        case other
    }

    struct Notice: Equatable {
        var kind: Kind
        var title: String
        /// The class it's for, e.g. "10 Maths A".
        var course = ""
        var due: Date?
        var hasTime = false
        /// Its page in Classroom.
        var link: URL?
    }

    /// Sent by Google Classroom (no-reply@classroom.google.com).
    static func isClassroom(_ senderEmail: String) -> Bool {
        guard let at = senderEmail.lastIndex(of: "@") else { return false }
        let domain = senderEmail[senderEmail.index(after: at)...].lowercased()
        return domain == "classroom.google.com" || domain.hasSuffix(".classroom.google.com")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    }

    private static let quoted = regex("[\"“«]([^\"“”«»]{1,300})[\"”»]")
    private static let singleQuoted = regex("(?<![a-z0-9])['‘]([^'‘’]{1,300})['’](?![a-z0-9])")
    private static let postedIn = regex("\\bposted an? new ([a-z ]{3,30}?) in ([^\\n]{1,120})$")
    private static let dueLine = regex("\\bdue(?: date)?:?[ \\t]+([^\\n]{2,60})")
    private static let classroomLink = regex("https://classroom\\.google\\.com/[^\\s\"'<>)\\]]+")

    /// What a Classroom email says. Nil if there's no telling what it's about.
    /// - Parameters:
    ///   - text: the email as plain text (or just Gmail's preview, if that's all there is).
    ///   - sent: when it was sent; "due tomorrow" counts from then.
    static func read(subject: String, text: String, html: String? = nil, sent: Date, calendar: Calendar = .current) -> Notice? {
        let lower = subject.lowercased().trimmingCharacters(in: .whitespaces)
        let body = text.lowercased()
        let kind: Kind
        if lower.hasPrefix("new assignment") || lower.hasPrefix("new quiz") || lower.hasPrefix("assignment:") {
            kind = .assignment
        } else if lower.hasPrefix("new question") {
            kind = .question
        } else if lower.hasPrefix("due ") || lower.hasPrefix("reminder") || lower.contains("is due") {
            kind = .reminder
        } else if lower.hasPrefix("returned") || lower.hasPrefix("graded") || lower.hasPrefix("grade ") || lower.hasPrefix("marked") {
            kind = .returned
        } else if body.contains("posted a new assignment") || body.contains("posted a new quiz") {
            kind = .assignment
        } else if body.contains("posted a new question") {
            kind = .question
        } else if body.contains("returned your work") || body.contains("returned:") {
            kind = .returned
        } else {
            kind = .other
        }

        var title = self.title(fromSubject: subject)
        // Long titles are cut short in the subject; the email itself has all of it.
        for ending in ["...", "…"] where title.hasSuffix(ending) {
            let start = String(title.dropLast(ending.count)).trimmingCharacters(in: .whitespaces)
            title = start
            if start.count >= 8, let line = text.components(separatedBy: "\n")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { $0.count <= 240 && $0.lowercased().hasPrefix(start.lowercased()) }) {
                title = line
            }
        }
        guard !title.isEmpty else { return nil }
        var notice = Notice(kind: kind, title: title)

        let whole = NSRange(text.startIndex..., in: text)
        if let match = postedIn?.firstMatch(in: text, options: [], range: whole), let range = Range(match.range(at: 2), in: text) {
            var course = text[range].trimmingCharacters(in: .whitespaces)
            // The sentence ends the class's name, whatever follows on the line.
            if let stop = course.range(of: ". ") { course = String(course[..<stop.lowerBound]) }
            if course.hasSuffix(".") { course.removeLast() }
            notice.course = String(course.prefix(80))
        }

        // "Due Nov 14, 11:59 PM", "Due: 14 Nov", "Due tomorrow": the first that reads as a date,
        // and one with a time over one without.
        var found: DueDateParser.Found?
        for source in [text, subject] {
            let range = NSRange(source.startIndex..., in: source)
            for match in dueLine?.matches(in: source, options: [], range: range) ?? [] {
                guard let part = Range(match.range(at: 1), in: source),
                      let date = DueDateParser.parse(String(source[part]), relativeTo: sent, calendar: calendar) else { continue }
                if found == nil || (found?.hasTime == false && date.hasTime) {
                    found = date
                }
            }
        }
        // Nothing dated in a year either side of the email is believable.
        if let date = found, abs(date.date.timeIntervalSince(sent)) < 370 * 24 * 3600 {
            notice.due = date.date
            notice.hasTime = date.hasTime
        }

        for source in [html, text].compactMap({ $0 }) {
            let range = NSRange(source.startIndex..., in: source)
            if let match = classroomLink?.firstMatch(in: source, options: [], range: range), let part = Range(match.range, in: source) {
                notice.link = URL(string: source[part].replacingOccurrences(of: "&amp;", with: "&"))
                break
            }
        }
        return notice
    }

    /// The name in quotes in "New assignment: "Essay draft"", or whatever follows the colon.
    static func title(fromSubject subject: String) -> String {
        let whole = NSRange(subject.startIndex..., in: subject)
        for pattern in [quoted, singleQuoted] {
            if let match = pattern?.firstMatch(in: subject, options: [], range: whole), let range = Range(match.range(at: 1), in: subject) {
                return subject[range].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let colon = subject.firstIndex(of: ":") {
            return subject[subject.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"“”'‘’"))
        }
        return ""
    }

    /// Puts what the email says into the planner. Returns whether the planner changed.
    @discardableResult
    static func apply(_ notice: Notice, emailID: String, emailLink: URL?, to planner: inout Planner,
                      now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch notice.kind {
        case .assignment, .question, .reminder:
            // A reminder about something already ticked off stays ticked off.
            var task = PlannerTask(title: notice.title, subject: notice.course, due: notice.due, hasTime: notice.hasTime,
                                   source: .classroom, emailID: emailID, link: notice.link ?? emailLink)
            task.minutes = notice.kind == .question ? 15 : PlannerTask.guessMinutes(for: notice.title)
            task.added = now
            return planner.take(task, calendar: calendar) != nil
        case .returned:
            return planner.finish(titled: notice.title, subject: notice.course, now: now)
        case .other:
            return false
        }
    }
}
