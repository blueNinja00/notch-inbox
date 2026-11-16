import Foundation

/// Lets the assistant see your timetable and change it. It's told what's on the timetable and
/// how to ask for a change: a <timetable>…</timetable> block of JSON at the end of its answer,
/// which the app applies and hides, noting what changed. Nothing changes unless you ask.
enum TimetableAgent {
    static let openTag = "<timetable>"
    static let closeTag = "</timetable>"

    /// The changes the assistant asks for. Every part is optional.
    struct Plan: Decodable, Equatable {
        struct Entry: Decodable, Equatable {
            var day: String
            var start: String
            /// When it ends. Without it, a class keeps the end it had, or takes the end of
            /// the period starting then, or runs for an hour.
            var end: String?
            var subject: String?
            var room: String?
            var teacher: String?
            var week: String?
        }

        struct Times: Decodable, Equatable {
            var start: String
            var end: String
        }

        var set: [Entry]?
        var clear: [Entry]?
        var weekends: Bool?
        var school: Times?
        /// The part of the day the timetable shows.
        var shown: Times?
    }

    // MARK: What the assistant is told

    /// How to change the timetable, for the assistant's instructions.
    static let instructions = """
    You can change the user's timetable when they ask you to: add, move or remove classes and activities, \
    or turn weekends on or off. Every class and activity has its own start and end time, any length, and several \
    can be at the same time. To do it, end your reply with one block in exactly this form (the app makes the \
    changes and hides the block):
    <timetable>{"set":[{"day":"Tue","start":"17:15","end":"18:00","subject":"Piano","room":"Studio","teacher":"Ms Kim"}],"clear":[{"day":"Wed","start":"18:00"}]}</timetable>
    - "day": Mon, Tue, Wed, Thu, Fri, Sat or Sun; several separated by commas ("Mon, Wed"); or "weekdays", "weekend" or "every day".
    - "start" and "end": 24-hour times, e.g. "17:15". A class already starting at that time on that day is changed; \
    otherwise a new one is added. Without "end", a changed class keeps its end, and a new one ends with the school \
    period starting then, or after an hour.
    - "subject" is the class or activity, "room" is where, "teacher" is who with. Leave out what you don't know.
    - "clear" removes what starts at that time on those days (or, if nothing starts then, what's on at that time).
    - You can also use "weekends" (true or false), "school": {"start":"08:30","end":"15:30"} (when school is one \
    block; the School blocks move with it), "shown": {"start":"06:00","end":"22:00"} (the part of the day the \
    timetable shows), and "week": "A" or "B" on an entry, for a two-week timetable.
    - Only include what you're changing, and say in plain words what you changed. Never use the block unless \
    the user wants their timetable changed.
    """

    /// The timetable in words: its bell times and what's on.
    static func describe(_ table: Timetable, now: Date, calendar: Calendar = .current) -> String {
        var lines: [String] = []
        let days = table.weekends ? "Monday to Sunday" : "Monday to Friday"
        var heading = "The user's timetable (they let you see and change it). Days shown: \(days), "
            + "from \(clock(table.shownStart)) to \(clock(table.shownEnd))."
        if table.twoWeeks {
            heading += " It runs over two weeks; this week is \(Timetable.weekName(table.week(of: now, calendar: calendar)))."
        }
        lines.append(heading)
        lines.append("The school day's bell times:")
        for period in table.periods {
            lines.append("\(clock(period.start))–\(clock(period.end)) \(period.name)\(period.isBreak ? " (break)" : "")")
        }
        var filled: [String] = []
        for week in table.twoWeeks ? [0, 1] : [0] {
            for day in 0..<table.dayCount {
                for event in table.events(day: day, week: week) {
                    var line = (table.twoWeeks ? "\(Timetable.weekName(week)) " : "")
                        + "\(Timetable.shortDayNames[day]) \(clock(event.start))–\(clock(event.end)) \(event.subject.trimmingCharacters(in: .whitespaces))"
                    if !event.room.isEmpty { line += ", where: \(event.room)" }
                    if !event.teacher.isEmpty { line += ", with: \(event.teacher)" }
                    filled.append(line)
                }
            }
        }
        lines.append(filled.isEmpty ? "Nothing is on it yet." : "What's on (each with its start and end):")
        lines += filled.prefix(200)
        let today = Timetable.dayIndex(of: now, calendar: calendar)
        lines.append("Today is \(Timetable.dayNames[today]), \(clock(Timetable.minuteOfDay(now, calendar: calendar))).")
        return lines.joined(separator: "\n")
    }

    /// 1020 → "17:00".
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
    }

    // MARK: Reading the answer

    /// The changes asked for at the end of an answer, if any, and the answer without them.
    static func extract(from text: String) -> (plan: Plan?, text: String) {
        guard let json = AgentBlock.json(in: text, tag: "timetable") else {
            return (nil, hidden(text))
        }
        let plan = try? JSONDecoder().decode(Plan.self, from: Data(json.utf8))
        return (plan, hidden(text))
    }

    /// The answer without any change block, including one still streaming in.
    static func hidden(_ text: String) -> String {
        AgentBlock.hidden(text)
    }

    // MARK: Making the changes

    /// Makes the changes and says what changed, e.g. ["Tue 5:15 pm: Piano (Studio)", "Wed 6 pm: cleared"].
    static func apply(_ plan: Plan, to table: inout Timetable, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var changes: [String] = []

        if let weekends = plan.weekends, weekends != table.weekends {
            table.weekends = weekends
            changes.append(weekends ? "Weekends on" : "Weekends off")
        }
        if let school = plan.school, table.schoolIsOneBlock, var block = table.periods.first,
           let start = time(school.start), let end = time(school.end) {
            block.start = start
            block.end = end
            if table.updatePeriod(block) {
                changes.append("School: \(ClockTime.long(start)) to \(ClockTime.long(end))")
            }
        }
        if let shown = plan.shown, let start = time(shown.start), let end = time(shown.end), end > start {
            table.setDay(start: start, end: end)
            changes.append("Shown: \(ClockTime.hour(table.dayStart)) to \(ClockTime.hour(table.dayEnd))")
        }
        for entry in plan.clear ?? [] {
            guard let minute = time(entry.start) else { continue }
            for (week, day, label) in places(for: entry, in: &table, minute: minute, now: now, calendar: calendar) {
                let onDay = table.events(day: day, week: week)
                let starting = onDay.filter { $0.start == minute }
                let gone = starting.isEmpty ? onDay.filter { $0.contains(minute) } : starting
                guard !gone.isEmpty else { continue }
                for event in gone {
                    table.removeEvent(event.id)
                }
                changes.append("\(label): cleared")
            }
        }
        for entry in plan.set ?? [] {
            guard let minute = time(entry.start) else { continue }
            let end = entry.end.flatMap { time($0) }
            let subject = (entry.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            for (week, day, label) in places(for: entry, in: &table, minute: minute, now: now, calendar: calendar) {
                if let existing = table.events(day: day, week: week).first(where: { $0.start == minute }) {
                    let sameSubject = subject.isEmpty || Timetable.subjectKey(existing.subject) == Timetable.subjectKey(subject)
                    var changed = existing
                    changed.subject = subject.isEmpty ? existing.subject : subject
                    changed.room = entry.room ?? (sameSubject ? existing.room : "")
                    changed.teacher = entry.teacher ?? (sameSubject ? existing.teacher : "")
                    changed.end = end ?? existing.end
                    guard changed != existing, !changed.isEmpty, table.update(changed) else { continue }
                    changes.append(line(label, changed, timed: end != nil))
                } else {
                    let finish = end ?? defaultEnd(for: minute, day: day, in: table)
                    let lesson = Timetable.Lesson(subject: subject, room: entry.room ?? "", teacher: entry.teacher ?? "")
                    guard !lesson.isEmpty, let added = table.addEvent(day: day, week: week, start: minute, end: finish, lesson: lesson) else { continue }
                    changes.append(line(label, added, timed: end != nil))
                }
            }
        }
        table.tidy()
        return changes
    }

    /// "Tue 5:15 pm: Piano (Studio), until 6 pm".
    private static func line(_ label: String, _ event: Timetable.Event, timed: Bool) -> String {
        "\(label): \(event.subject)" + (event.room.isEmpty ? "" : " (\(event.room))") + (timed ? ", until \(ClockTime.hour(event.end))" : "")
    }

    /// When a new class at a time ends: with the school period that starts then (on a
    /// school day), or an hour later.
    static func defaultEnd(for minute: Int, day: Int, in table: Timetable) -> Int {
        if day < 5, let period = table.periods.first(where: { !$0.isBreak && $0.start == minute }) {
            return period.end
        }
        return min(24 * 60, minute + 60)
    }

    /// The days (and weeks) an entry means, each with its label: "Tue 5:15 pm".
    private static func places(for entry: Plan.Entry, in table: inout Timetable, minute: Int, now: Date,
                               calendar: Calendar) -> [(week: Int, day: Int, label: String)] {
        let days = self.days(entry.day, table: table, now: now, calendar: calendar)
        if days.contains(where: { $0 >= 5 }) && !table.weekends {
            table.weekends = true
        }
        let weeks: [Int]
        switch entry.week?.uppercased().trimmingCharacters(in: .whitespaces) {
        case "A"?, "WEEK A"?: weeks = [0]
        case "B"?, "WEEK B"?: weeks = table.twoWeeks ? [1] : [0]
        default: weeks = table.twoWeeks ? [0, 1] : [0]
        }
        var result: [(week: Int, day: Int, label: String)] = []
        for week in weeks {
            for day in days {
                let label = (table.twoWeeks && weeks.count == 1 ? "\(Timetable.weekName(week)) " : "")
                    + "\(Timetable.shortDayNames[day]) \(ClockTime.hour(minute))"
                result.append((week, day, label))
            }
        }
        return result
    }

    /// 24-hour times first ("06:00" is 6 am), then the way people write them ("5 pm").
    static func time(_ text: String) -> Int? {
        clockMinutes(text) ?? ClockTime.parse(text)
    }

    /// "17:00" or "6:00" read as 24-hour time.
    private static func clockMinutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0..<60).contains(minute), hour * 60 + minute <= 24 * 60 else { return nil }
        return hour * 60 + minute
    }

    /// "Mon", "monday", "Mon, Wed", "weekdays", "weekend", "every day", "today", "tomorrow".
    static func days(_ text: String, table: Timetable, now: Date, calendar: Calendar = .current) -> [Int] {
        var days: [Int] = []
        let normalized = text.lowercased().replacingOccurrences(of: " and ", with: ",")
        for part in normalized.split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "&" }) {
            let word = part.trimmingCharacters(in: .whitespaces)
            switch word {
            case "weekdays", "weekday", "school days", "mon-fri", "monday to friday":
                days += 0..<5
            case "weekend", "weekends":
                days += [5, 6]
            case "every day", "everyday", "daily", "all":
                days += 0..<table.dayCount
            case "today":
                days.append(Timetable.dayIndex(of: now, calendar: calendar))
            case "tomorrow":
                if let next = calendar.date(byAdding: .day, value: 1, to: now) {
                    days.append(Timetable.dayIndex(of: next, calendar: calendar))
                }
            default:
                if let index = Timetable.shortDayNames.firstIndex(where: { word.hasPrefix($0.lowercased()) }) {
                    days.append(index)
                }
            }
        }
        var seen = Set<Int>()
        return days.filter { seen.insert($0).inserted }
    }
}
