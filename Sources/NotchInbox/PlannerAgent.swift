import Foundation

/// Lets the assistant see your planner and change it. It's told what homework and exams are
/// in it and how to ask for a change: a <planner>…</planner> block of JSON at the end of its
/// answer, which the app applies and hides, noting what changed. Nothing changes unless you ask.
enum PlannerAgent {
    static let openTag = "<planner>"
    static let closeTag = "</planner>"

    /// The changes the assistant asks for. Every part is optional.
    struct Plan: Decodable, Equatable {
        struct Item: Decodable, Equatable {
            var title: String
            var subject: String?
            /// When homework is due, or (as "date") when an exam is.
            var due: String?
            var date: String?
            var minutes: Int?
            var study: Int?
            var place: String?
            var notes: String?
            var newTitle: String?

            enum CodingKeys: String, CodingKey {
                case title, subject, due, date, minutes, study, place, notes, newTitle
            }

            init(title: String, subject: String? = nil, due: String? = nil, date: String? = nil, minutes: Int? = nil,
                 study: Int? = nil, place: String? = nil, notes: String? = nil, newTitle: String? = nil) {
                self.title = title
                self.subject = subject
                self.due = due
                self.date = date
                self.minutes = minutes
                self.study = study
                self.place = place
                self.notes = notes
                self.newTitle = newTitle
            }

            init(from decoder: Decoder) throws {
                // A bare string is just a title.
                if let single = try? decoder.singleValueContainer(), let title = try? single.decode(String.self) {
                    self.init(title: title)
                    return
                }
                let values = try decoder.container(keyedBy: CodingKeys.self)
                self.init(title: try values.decode(String.self, forKey: .title),
                          subject: try? values.decodeIfPresent(String.self, forKey: .subject),
                          due: try? values.decodeIfPresent(String.self, forKey: .due),
                          date: try? values.decodeIfPresent(String.self, forKey: .date),
                          minutes: Item.number(values, .minutes),
                          study: Item.number(values, .study),
                          place: try? values.decodeIfPresent(String.self, forKey: .place),
                          notes: try? values.decodeIfPresent(String.self, forKey: .notes),
                          newTitle: try? values.decodeIfPresent(String.self, forKey: .newTitle))
            }

            /// Minutes as a number, however the model wrote it: 45, 45.0 or "45".
            private static func number(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
                if let whole = try? values.decodeIfPresent(Int.self, forKey: key) { return whole }
                if let part = try? values.decodeIfPresent(Double.self, forKey: key) { return Int(part.rounded()) }
                if let text = try? values.decodeIfPresent(String.self, forKey: key) {
                    return Int(text.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber })
                }
                return nil
            }
        }

        var add: [Item]?
        var exams: [Item]?
        var done: [Item]?
        var undone: [Item]?
        var remove: [Item]?
        var update: [Item]?
    }

    // MARK: What the assistant is told

    /// How to change the planner, for the assistant's instructions.
    static let instructions = """
    You can change the user's planner (their homework and exams) when they ask you to: add homework or an exam, \
    tick homework off, change when something is due, or remove it. To do it, end your reply with one block in \
    exactly this form (the app makes the changes and hides the block):
    <planner>{"add":[{"title":"Maths worksheet","subject":"Maths","due":"2026-11-13 16:00","minutes":45}],"exams":[{"title":"Yearly exam","subject":"Science","date":"2026-11-20 09:00","place":"Hall","study":120}],"done":["English essay"],"update":[{"title":"History notes","due":"2026-11-18"}],"remove":["Old task"]}</planner>
    - Dates are "YYYY-MM-DD" or "YYYY-MM-DD HH:MM" in 24-hour time. Work out the real date from what the user says \
    ("Friday") and today's date. Leave "due" out for homework with no due date.
    - "minutes" is how long homework should take. "study" is how many minutes of revision to plan before an exam.
    - "done", "undone" and "remove" take titles as the planner lists them. "update" finds homework or an exam by \
    "title" and changes what you include; "newTitle" renames it.
    - Only include what you're changing, and say in plain words what you changed. Never use the block unless \
    the user wants their planner changed; to say what's due, just answer from the list.
    """

    /// The planner in words: what's to do, what's coming up, and today's plan.
    static func describe(_ planner: Planner, sessions: [StudySession] = [], now: Date, calendar: Calendar = .current) -> String {
        var lines = ["The user's planner (they let you see and change it)."]
        let open = planner.open(now: now)
        if open.isEmpty {
            lines.append("Homework to do: none.")
        } else {
            lines.append("Homework to do:")
            for task in open.prefix(40) {
                var line = "- \(task.title)"
                if !task.subject.isEmpty { line += " [\(task.subject)]" }
                if let due = task.due {
                    line += ", due \(stamp(due, hasTime: task.hasTime, calendar: calendar)) (\(when(due, now: now, calendar: calendar)))"
                    if task.isOverdue(now: now, calendar: calendar) { line += ", overdue" }
                } else {
                    line += ", no due date"
                }
                line += ", about \(task.minutes) min"
                lines.append(line)
            }
            if open.count > 40 { lines.append("…and \(open.count - 40) more.") }
        }
        let exams = planner.upcomingExams(now: now, calendar: calendar)
        if exams.isEmpty {
            lines.append("Exams coming up: none.")
        } else {
            lines.append("Exams coming up:")
            for exam in exams.prefix(15) {
                var line = "- \(exam.title)"
                if !exam.subject.isEmpty { line += " [\(exam.subject)]" }
                line += ", \(stamp(exam.date, hasTime: exam.hasTime, calendar: calendar)) (\(when(exam.date, now: now, calendar: calendar)))"
                if !exam.place.isEmpty { line += ", at \(exam.place)" }
                lines.append(line)
            }
        }
        let finished = planner.finished.prefix(6).map { $0.title }
        if !finished.isEmpty {
            lines.append("Finished lately: " + finished.joined(separator: "; ") + ".")
        }
        let today = sessions.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if !today.isEmpty {
            let parts = today.prefix(8).map { "\(DueText.time($0.start, calendar: calendar)) \($0.title) (\(DueText.length($0.minutes)))" }
            lines.append("The app's study plan for today: " + parts.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// "2026-11-13 16:00", or just the day.
    static func stamp(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return hasTime ? day + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0) : day
    }

    /// "Fri, tomorrow".
    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let day = Timetable.shortDayNames[Timetable.dayIndex(of: date, calendar: calendar)]
        return "\(day), \(DueText.countdown(to: date, now: now, calendar: calendar))"
    }

    // MARK: Reading the answer

    /// The changes asked for at the end of an answer, if any, and the answer without them.
    static func extract(from text: String) -> (plan: Plan?, text: String) {
        guard let json = AgentBlock.json(in: text, tag: "planner") else {
            return (nil, AgentBlock.hidden(text))
        }
        let plan = try? JSONDecoder().decode(Plan.self, from: Data(json.utf8))
        return (plan, AgentBlock.hidden(text))
    }

    // MARK: Making the changes

    /// Makes the changes and says what changed, e.g. ["Added: Maths worksheet (Fri 13 Nov, 4 pm)", "Done: English essay"].
    static func apply(_ plan: Plan, to planner: inout Planner, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var changes: [String] = []

        func date(_ text: String?) -> DueDateParser.Found? {
            guard let text = text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return DueDateParser.parse(text, relativeTo: now, calendar: calendar)
        }
        func clean(_ text: String?, limit: Int = 140) -> String {
            String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        }

        for item in plan.add ?? [] {
            let title = clean(item.title)
            guard !title.isEmpty else { continue }
            let subject = clean(item.subject, limit: 60)
            if let index = planner.taskIndex(titled: title, subject: subject), !planner.tasks[index].done { continue }
            var task = PlannerTask(title: title, subject: subject, source: .assistant)
            if let due = date(item.due ?? item.date) {
                task.due = due.date
                task.hasTime = due.hasTime
            }
            task.minutes = item.minutes.map { max(5, min($0, 600)) } ?? PlannerTask.guessMinutes(for: title)
            task.notes = clean(item.notes, limit: 500)
            task.added = now
            planner.add(task)
            changes.append("Added: \(title)" + (task.due.map { " (\(DueText.full($0, hasTime: task.hasTime, calendar: calendar)))" } ?? ""))
        }

        for item in plan.exams ?? [] {
            let title = clean(item.title)
            guard !title.isEmpty, let when = date(item.date ?? item.due) else { continue }
            var exam = Exam(title: title, subject: clean(item.subject, limit: 60), date: when.date, hasTime: when.hasTime,
                            place: clean(item.place, limit: 60), source: .assistant)
            if let study = item.study { exam.studyMinutes = max(0, min(study, 1200)) }
            exam.notes = clean(item.notes, limit: 500)
            exam.added = now
            if planner.take(exam, calendar: calendar) != nil {
                changes.append("Exam added: \(exam.name) (\(DueText.full(exam.date, hasTime: exam.hasTime, calendar: calendar)))")
            }
        }

        for item in plan.update ?? [] {
            let open = planner.tasks.filter { !$0.done }
            if let task = find(item.title, in: open, title: { $0.title }) ?? find(item.title, in: planner.tasks, title: { $0.title }) {
                var changed = task
                if let renamed = item.newTitle.map({ clean($0) }), !renamed.isEmpty { changed.title = renamed }
                if let subject = item.subject { changed.subject = clean(subject, limit: 60) }
                if let due = date(item.due ?? item.date) {
                    changed.due = due.date
                    changed.hasTime = due.hasTime
                } else if let text = item.due, ["", "none", "no due date"].contains(text.lowercased().trimmingCharacters(in: .whitespaces)) {
                    changed.due = nil
                    changed.hasTime = false
                }
                if let minutes = item.minutes { changed.minutes = max(5, min(minutes, 600)) }
                if let notes = item.notes { changed.notes = clean(notes, limit: 500) }
                guard changed != task else { continue }
                planner.update(changed)
                changes.append("Changed: \(changed.title)" + (changed.due.map { " (\(DueText.full($0, hasTime: changed.hasTime, calendar: calendar)))" } ?? ""))
            } else if let exam = find(item.title, in: planner.exams, title: { $0.title }) {
                var changed = exam
                if let renamed = item.newTitle.map({ clean($0) }), !renamed.isEmpty { changed.title = renamed }
                if let subject = item.subject { changed.subject = clean(subject, limit: 60) }
                if let when = date(item.date ?? item.due) {
                    changed.date = when.date
                    changed.hasTime = when.hasTime
                }
                if let place = item.place { changed.place = clean(place, limit: 60) }
                if let study = item.study ?? item.minutes { changed.studyMinutes = max(0, min(study, 1200)) }
                if let notes = item.notes { changed.notes = clean(notes, limit: 500) }
                guard changed != exam else { continue }
                planner.update(changed)
                changes.append("Changed: \(changed.name) (\(DueText.full(changed.date, hasTime: changed.hasTime, calendar: calendar)))")
            }
        }

        for item in plan.done ?? [] {
            if let task = find(item.title, in: planner.tasks.filter({ !$0.done }), title: { $0.title }) {
                planner.setDone(task.id, true, now: now)
                changes.append("Done: \(task.title)")
            }
        }
        for item in plan.undone ?? [] {
            if let task = find(item.title, in: planner.tasks.filter({ $0.done }), title: { $0.title }) {
                planner.setDone(task.id, false, now: now)
                changes.append("Back on the list: \(task.title)")
            }
        }
        for item in plan.remove ?? [] {
            if let task = find(item.title, in: planner.tasks, title: { $0.title }) {
                planner.removeTask(task.id)
                changes.append("Removed: \(task.title)")
            } else if let exam = find(item.title, in: planner.exams, title: { $0.title }) {
                planner.removeExam(exam.id)
                changes.append("Removed: \(exam.name)")
            }
        }
        return changes
    }

    /// The one that goes by this title: the same letters and digits, or failing that, the only
    /// one whose title contains it (or is contained in it).
    static func find<Item>(_ title: String, in items: [Item], title name: (Item) -> String) -> Item? {
        let wanted = Planner.plain(title)
        guard !wanted.isEmpty else { return nil }
        if let exact = items.last(where: { Planner.plain(name($0)) == wanted }) {
            return exact
        }
        guard wanted.count >= 4 else { return nil }
        let near = items.filter { item in
            let plain = Planner.plain(name(item))
            return plain.count >= 4 && (plain.contains(wanted) || wanted.contains(plain))
        }
        return near.count == 1 ? near.first : nil
    }
}
