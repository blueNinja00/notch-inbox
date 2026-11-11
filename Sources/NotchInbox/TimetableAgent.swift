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
        var before: Int?
        var after: Int?
        var weekends: Bool?
        var school: Times?
    }

    // MARK: What the assistant is told

    /// How to change the timetable, for the assistant's instructions.
    static let instructions = """
    You can change the user's timetable when they ask you to: add, move or remove classes and activities, \
    change the hour blocks around school, or turn weekends on or off. To do it, end your reply with one block \
    in exactly this form (the app makes the changes and hides the block):
    <timetable>{"set":[{"day":"Tue","start":"17:00","subject":"Soccer training","room":"Oval","teacher":"Coach Sam"}],"clear":[{"day":"Wed","start":"18:00"}]}</timetable>
    - "day": Mon, Tue, Wed, Thu, Fri, Sat or Sun; several separated by commas ("Mon, Wed"); or "weekdays", "weekend" or "every day".
    - "start": the 24-hour start time of a row of the timetable, e.g. "17:00".
    - "subject" is the class or activity, "room" is where, "teacher" is who with. Leave out what you don't know.
    - You can also use "before" (hour blocks before school, 0 to 4), "after" (hour blocks after school, 0 to 8), \
    "weekends" (true or false), "school": {"start":"08:30","end":"15:30"} (when school is one block), and \
    "week": "A" or "B" on an entry, for a two-week timetable.
    - Only include what you're changing, and say in plain words what you changed. Never use the block unless \
    the user wants their timetable changed.
    """

    /// The timetable in words: its rows and what's in them.
    static func describe(_ table: Timetable, now: Date, calendar: Calendar = .current) -> String {
        var lines: [String] = []
        let days = table.weekends ? "Monday to Sunday" : "Monday to Friday"
        var heading = "The user's timetable (they let you see and change it). Days shown: \(days)."
        if table.twoWeeks {
            heading += " It runs over two weeks; this week is \(Timetable.weekName(table.week(of: now, calendar: calendar)))."
        }
        lines.append(heading)
        lines.append("Rows each day:")
        for row in table.rows {
            let kind: String
            if row.isActivity {
                kind = row.start < table.schoolStart ? "hour block before school" : "hour block after school"
            } else if row.isBreak {
                kind = "\(row.name) (break)"
            } else {
                kind = row.name
            }
            lines.append("\(clock(row.start))–\(clock(row.end)) \(kind)")
        }
        var filled: [String] = []
        for week in table.twoWeeks ? [0, 1] : [0] {
            for day in 0..<table.dayCount {
                for entry in table.day(day, week: week) {
                    guard let lesson = entry.lesson, !lesson.isEmpty else { continue }
                    var line = (table.twoWeeks ? "\(Timetable.weekName(week)) " : "")
                        + "\(Timetable.shortDayNames[day]) \(clock(entry.period.start)) \(lesson.subject.trimmingCharacters(in: .whitespaces))"
                    if !lesson.room.isEmpty { line += ", where: \(lesson.room)" }
                    if !lesson.teacher.isEmpty { line += ", with: \(lesson.teacher)" }
                    filled.append(line)
                }
            }
        }
        lines.append(filled.isEmpty ? "Nothing is filled in yet." : "What's in it (empty slots aren't listed):")
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

    /// Makes the changes and says what changed, e.g. ["Tue 5 pm: Soccer training", "Wed 6 pm: cleared"].
    static func apply(_ plan: Plan, to table: inout Timetable, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var changes: [String] = []

        if let weekends = plan.weekends, weekends != table.weekends {
            table.weekends = weekends
            changes.append(weekends ? "Weekends on" : "Weekends off")
        }
        if let school = plan.school, table.schoolIsOneBlock, var block = table.periods.first,
           let start = ClockTime.parse(school.start), let end = ClockTime.parse(school.end) {
            block.start = start
            block.end = end
            if table.updatePeriod(block) {
                changes.append("School: \(ClockTime.long(start)) to \(ClockTime.long(end))")
            }
        }
        if plan.before != nil || plan.after != nil {
            let before = table.beforeSchool
            let after = table.afterSchool
            table.setBlocks(before: plan.before, after: plan.after)
            if table.beforeSchool != before || table.afterSchool != after {
                changes.append("Hour blocks: \(table.beforeSchool) before school, \(table.afterSchool) after")
            }
        }

        for entry in plan.clear ?? [] {
            for slot in slots(for: entry, in: &table, now: now, calendar: calendar) where table.lesson(at: slot.slot) != nil {
                table.setLesson(nil, at: slot.slot)
                changes.append("\(slot.label): cleared")
            }
        }
        for entry in plan.set ?? [] {
            let subject = (entry.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            for slot in slots(for: entry, in: &table, now: now, calendar: calendar) {
                let existing = table.lesson(at: slot.slot)
                let sameSubject = existing.map { Timetable.subjectKey($0.subject) == Timetable.subjectKey(subject) || subject.isEmpty } ?? false
                let lesson = Timetable.Lesson(subject: subject.isEmpty ? (existing?.subject ?? "") : subject,
                                              room: entry.room ?? (sameSubject ? existing?.room ?? "" : ""),
                                              teacher: entry.teacher ?? (sameSubject ? existing?.teacher ?? "" : ""))
                guard !lesson.isEmpty, lesson != existing else { continue }
                table.setLesson(lesson, at: slot.slot)
                changes.append("\(slot.label): \(lesson.subject)" + (lesson.room.isEmpty ? "" : " (\(lesson.room))"))
            }
        }
        table.tidy()
        return changes
    }

    /// The slots an entry means: its days (and weeks) at the row starting at (or covering) its time.
    private static func slots(for entry: Plan.Entry, in table: inout Timetable, now: Date,
                              calendar: Calendar) -> [(slot: Timetable.Slot, label: String)] {
        // 24-hour times first ("06:00" is 6 am), then the way people write them ("5 pm").
        guard let minute = clockMinutes(entry.start) ?? ClockTime.parse(entry.start) else { return [] }
        let rows = table.rows
        guard let row = rows.first(where: { $0.start == minute }) ?? rows.first(where: { $0.contains(minute) }), !row.isBreak else {
            return []
        }
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
        var result: [(slot: Timetable.Slot, label: String)] = []
        for week in weeks {
            for day in days {
                let label = (table.twoWeeks && weeks.count == 1 ? "\(Timetable.weekName(week)) " : "")
                    + "\(Timetable.shortDayNames[day]) \(ClockTime.hour(row.start))"
                result.append((Timetable.Slot(week: week, day: day, period: row.id), label))
            }
        }
        return result
    }

    /// "17:00" or "6:00" read as 24-hour time.
    private static func clockMinutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
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
