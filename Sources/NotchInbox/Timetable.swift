import Foundation
#if canImport(Combine)
import Combine
#endif

/// Times of day as minutes after midnight: reading what you type, and showing them.
enum ClockTime {
    /// "8:50", "08.50", "850", "1:10 pm", "13:10", "9am" → minutes after midnight. Without
    /// am or pm, 1 to 6 o'clock count as afternoon, since that's when school is on.
    static func parse(_ typed: String) -> Int? {
        var text = typed.lowercased().filter { !$0.isWhitespace }
        var half: String?
        for suffix in ["am", "pm", "a", "p"] where text.hasSuffix(suffix) {
            half = String(suffix.prefix(1))
            text = String(text.dropLast(suffix.count))
            break
        }
        guard !text.isEmpty else { return nil }

        var hour: Int
        var minute = 0
        if let separator = text.firstIndex(where: { $0 == ":" || $0 == "." }) {
            guard let h = Int(text[..<separator]), let m = Int(text[text.index(after: separator)...]),
                  text[text.index(after: separator)...].count == 2 else { return nil }
            hour = h
            minute = m
        } else if text.allSatisfy(\.isNumber), (3...4).contains(text.count), let number = Int(text) {
            hour = number / 100
            minute = number % 100
        } else if text.allSatisfy(\.isNumber), (1...2).contains(text.count), let number = Int(text) {
            hour = number
        } else {
            return nil
        }
        guard (0...59).contains(minute) else { return nil }

        switch half {
        case "a"?:
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
        case "p"?:
            guard (1...12).contains(hour) else { return nil }
            if hour != 12 { hour += 12 }
        default:
            guard (0...23).contains(hour) else { return nil }
            if (1...6).contains(hour) { hour += 12 }
        }
        return hour * 60 + minute
    }

    /// 530 → "8:50", 790 → "1:10".
    static func short(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 12
        return "\(hour == 0 ? 12 : hour):\(String(format: "%02d", minutes % 60))"
    }

    /// 960 → "4 pm", 990 → "4:30 pm": for hour blocks.
    static func hour(_ minutes: Int) -> String {
        let suffix = minutes / 60 % 24 < 12 ? " am" : " pm"
        let hour = (minutes / 60) % 12
        return (minutes % 60 == 0 ? "\(hour == 0 ? 12 : hour)" : short(minutes)) + suffix
    }

    /// 530 → "8:50 am", 790 → "1:10 pm".
    static func long(_ minutes: Int) -> String {
        short(minutes) + (minutes / 60 % 24 < 12 ? " am" : " pm")
    }
}

/// Your timetable: the school day's periods (classes and breaks) with an hour block for each
/// hour before and after school, for extracurriculars, and what's on in each, Monday to
/// Friday (or the whole week). It can run over two weeks (Week A and Week B).
struct Timetable: Codable, Equatable {
    struct Period: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        /// Minutes after midnight.
        var start: Int
        var end: Int
        /// Recess, lunch and the like: shown as a slim row across every day.
        var isBreak: Bool
        /// An hour before or after school, for extracurriculars. Worked out from the school
        /// day, never saved.
        var isActivity = false

        enum CodingKeys: String, CodingKey {
            case id, name, start, end, isBreak
        }

        var times: String { "\(ClockTime.short(start))–\(ClockTime.short(end))" }

        func contains(_ minute: Int) -> Bool { minute >= start && minute < end }
    }

    struct Lesson: Codable, Equatable {
        var subject: String
        var room: String
        var teacher: String

        init(subject: String, room: String = "", teacher: String = "") {
            self.subject = subject
            self.room = room
            self.teacher = teacher
        }

        var isEmpty: Bool {
            [subject, room, teacher].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        /// "B12 · Ms Lee", or whichever of the two there is.
        var details: String {
            [room, teacher].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// Where a lesson sits: week of the cycle (0 = A, 1 = B), day (0 = Monday … 6 = Sunday), period.
    struct Slot: Hashable {
        var week: Int
        var day: Int
        var period: UUID
    }

    /// The school day's periods, in time order.
    private(set) var periods: [Period]
    /// Keyed "week-day-period".
    private(set) var lessons: [String: Lesson]
    /// Each subject's colour (lowercased name → place in the palette), so all its lessons match.
    private(set) var subjectColours: [String: Int]
    var twoWeeks: Bool
    /// A Monday of a Week A.
    var weekA: Date
    /// How many hour blocks come before school, ending when school starts.
    private(set) var beforeSchool: Int
    /// How many hour blocks come after school, starting when school ends.
    private(set) var afterSchool: Int
    /// Saturday and Sunday too, for weekend activities.
    var weekends: Bool
    /// The version of the day it was saved with. 2: school as one block in a 6 am to 10 pm day.
    private(set) var layout: Int

    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let shortDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let colourCount = 8
    static let standardBefore = 2
    static let standardAfter = 6
    /// The day runs from 6 am to 10 pm to start with.
    static let dayStart = 6 * 60
    static let dayEnd = 22 * 60
    static let currentLayout = 2
    static let schoolSubject = "School"
    static let maxBefore = 4
    static let maxAfter = 8

    static func weekName(_ week: Int) -> String { week == 1 ? "Week B" : "Week A" }

    /// Days on the timetable: Monday to Friday, or the whole week.
    var dayCount: Int { weekends ? 7 : 5 }

    private static func period(_ name: String, _ start: String, _ end: String, isBreak: Bool = false) -> Period {
        Period(id: UUID(), name: name, start: ClockTime.parse(start) ?? 0, end: ClockTime.parse(end) ?? 0, isBreak: isBreak)
    }

    /// School as one block, 8 am to 4 pm.
    static func schoolBlock() -> [Period] {
        [period("School", "8:00", "4:00")]
    }

    /// School split into periods, 8 am to 4 pm: seven periods, recess and lunch.
    static func schoolPeriods() -> [Period] {
        [
            period("Period 1", "8:00", "9:00"),
            period("Period 2", "9:00", "10:00"),
            period("Period 3", "10:00", "11:00"),
            period("Recess", "11:00", "11:20", isBreak: true),
            period("Period 4", "11:20", "12:20"),
            period("Period 5", "12:20", "1:20"),
            period("Lunch", "1:20", "2:00", isBreak: true),
            period("Period 6", "2:00", "3:00"),
            period("Period 7", "3:00", "4:00"),
        ]
    }

    /// The day build 15 started everyone on (8:50 to 2:50).
    private static let firstStandard: [(String, Int, Int, Bool)] = [
        ("Period 1", 530, 590, false), ("Period 2", 590, 650, false), ("Recess", 650, 670, true),
        ("Period 3", 670, 730, false), ("Period 4", 730, 790, false), ("Lunch", 790, 830, true),
        ("Period 5", 830, 890, false),
    ]

    /// A new timetable: school as one block from 8 to 4, in a day from 6 am to 10 pm with an
    /// hour block for each hour around school.
    static func standard(now: Date = Date(), calendar: Calendar = .current) -> Timetable {
        var table = Timetable(periods: schoolBlock(), lessons: [:], subjectColours: [:], twoWeeks: false,
                              weekA: monday(of: now, calendar: calendar), beforeSchool: standardBefore,
                              afterSchool: standardAfter, weekends: false)
        table.fillSchool()
        return table
    }

    init(periods: [Period], lessons: [String: Lesson], subjectColours: [String: Int], twoWeeks: Bool,
         weekA: Date, beforeSchool: Int, afterSchool: Int, weekends: Bool, layout: Int = Timetable.currentLayout) {
        self.periods = periods
        self.lessons = lessons
        self.subjectColours = subjectColours
        self.twoWeeks = twoWeeks
        self.weekA = weekA
        self.beforeSchool = beforeSchool
        self.afterSchool = afterSchool
        self.weekends = weekends
        self.layout = layout
    }

    /// Reads a saved timetable. One from builds 15 to 17 moves to the new day: if its school
    /// day was still the one it started with, school becomes one block from 8 to 4; either
    /// way the hour blocks then run from 6 am to 10 pm.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        periods = try values.decode([Period].self, forKey: .periods)
        lessons = try values.decode([String: Lesson].self, forKey: .lessons)
        subjectColours = try values.decode([String: Int].self, forKey: .subjectColours)
        twoWeeks = try values.decode(Bool.self, forKey: .twoWeeks)
        weekA = try values.decode(Date.self, forKey: .weekA)
        weekends = try values.decodeIfPresent(Bool.self, forKey: .weekends) ?? false
        beforeSchool = try values.decodeIfPresent(Int.self, forKey: .beforeSchool) ?? Timetable.standardBefore
        afterSchool = try values.decodeIfPresent(Int.self, forKey: .afterSchool) ?? Timetable.standardAfter
        layout = try values.decodeIfPresent(Int.self, forKey: .layout) ?? 0
        if layout < Timetable.currentLayout {
            if matches(Timetable.firstStandard) || matches(Timetable.schoolPeriods()) {
                useSchoolBlock()
            }
            spanDay()
            layout = Timetable.currentLayout
        }
    }

    private func matches(_ day: [(String, Int, Int, Bool)]) -> Bool {
        periods.count == day.count && zip(periods, day).allSatisfy { period, other in
            period.name == other.0 && period.start == other.1 && period.end == other.2 && period.isBreak == other.3
        }
    }

    private func matches(_ day: [Period]) -> Bool {
        matches(day.map { ($0.name, $0.start, $0.end, $0.isBreak) })
    }

    /// School is one block (rather than periods).
    var schoolIsOneBlock: Bool { periods.count == 1 }

    /// Hour blocks for every hour from 6 am to school, and from school to 10 pm.
    mutating func spanDay() {
        setBlocks(before: max(0, schoolStart - Timetable.dayStart) / 60, after: max(0, Timetable.dayEnd - schoolEnd) / 60)
    }

    /// "School" in the school block on every weekday that has nothing else in it.
    mutating func fillSchool() {
        guard schoolIsOneBlock, let school = periods.first else { return }
        for week in 0...1 {
            for day in 0..<5 {
                let key = "\(week)-\(day)-\(school.id.uuidString)"
                if lessons[key] == nil {
                    lessons[key] = Lesson(subject: Timetable.schoolSubject)
                }
            }
        }
        let name = Timetable.subjectKey(Timetable.schoolSubject)
        if subjectColours[name] == nil {
            subjectColours[name] = freshColour()
        }
    }

    var isEmpty: Bool { lessons.isEmpty }

    /// When school starts and ends: the first and last period.
    var schoolStart: Int { periods.first?.start ?? 8 * 60 }
    var schoolEnd: Int { periods.map { $0.end }.max() ?? 16 * 60 }

    /// Hour blocks before school have IDs that stay the same when school times change, so
    /// what you put in them stays put: 1 is the hour just before school, 2 the one before that.
    static func blockID(before: Bool, number: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-4000-8000-%012X", before ? 0xB10C_BEF0 : 0xB10C_AF7E, number))!
    }

    /// Every row of the day, earliest first: hour blocks before school, the school day, hour
    /// blocks after.
    var rows: [Period] {
        var rows: [Period] = []
        let before = min(beforeSchool, schoolStart / 60)
        if before > 0 {
            for number in stride(from: before, through: 1, by: -1) {
                let start = schoolStart - number * 60
                rows.append(Period(id: Timetable.blockID(before: true, number: number), name: "Before school",
                                   start: start, end: start + 60, isBreak: false, isActivity: true))
            }
        }
        rows += periods
        let after = min(afterSchool, (24 * 60 - schoolEnd) / 60)
        if after > 0 {
            for number in 1...after {
                let start = schoolEnd + (number - 1) * 60
                rows.append(Period(id: Timetable.blockID(before: false, number: number), name: "After school",
                                   start: start, end: start + 60, isBreak: false, isActivity: true))
            }
        }
        return rows
    }

    func period(_ id: UUID?) -> Period? {
        guard let id = id else { return nil }
        return rows.first { $0.id == id }
    }

    /// How many hour blocks before and after school (0 to 4 before, 0 to 8 after). What's
    /// in a block you take away is kept, and comes back if you add it again.
    mutating func setBlocks(before: Int? = nil, after: Int? = nil) {
        if let before = before {
            beforeSchool = max(0, min(Timetable.maxBefore, before))
        }
        if let after = after {
            afterSchool = max(0, min(Timetable.maxAfter, after))
        }
    }

    // MARK: Lessons

    private func key(_ slot: Slot) -> String {
        "\(twoWeeks ? slot.week : 0)-\(slot.day)-\(slot.period.uuidString)"
    }

    func lesson(at slot: Slot) -> Lesson? {
        lessons[key(slot)]
    }

    /// A subject's name for matching: "  maths " and "Maths" are the same subject.
    static func subjectKey(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Puts a lesson in a slot (nil or blank clears it), as typed so far. A new subject gets
    /// its own colour. `tidy()` trims it once you've finished editing.
    mutating func setLesson(_ lesson: Lesson?, at slot: Slot) {
        guard let lesson = lesson, !lesson.isEmpty else {
            lessons[key(slot)] = nil
            return
        }
        lessons[key(slot)] = lesson
        let name = Timetable.subjectKey(lesson.subject)
        if !name.isEmpty && subjectColours[name] == nil {
            subjectColours[name] = freshColour()
        }
    }

    /// After editing: spaces trimmed, blank lessons gone, and colours kept only for subjects
    /// still on the timetable.
    mutating func tidy() {
        var tidied: [String: Lesson] = [:]
        for (key, lesson) in lessons {
            let clean = Lesson(subject: lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines),
                               room: lesson.room.trimmingCharacters(in: .whitespacesAndNewlines),
                               teacher: lesson.teacher.trimmingCharacters(in: .whitespacesAndNewlines))
            if !clean.isEmpty {
                tidied[key] = clean
            }
        }
        lessons = tidied
        let inUse = Set(tidied.values.map { Timetable.subjectKey($0.subject) })
        subjectColours = subjectColours.filter { inUse.contains($0.key) }
    }

    /// Every subject (and activity) on the timetable, A to Z, as you first typed it.
    var subjects: [String] {
        var seen: [String: String] = [:]
        for lesson in lessons.values {
            let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { continue }
            let name = subject.lowercased()
            if seen[name] == nil || subject < seen[name]! {
                seen[name] = subject
            }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The room and teacher another lesson of this subject has, to fill in for you.
    func usual(for subject: String) -> Lesson? {
        let name = Timetable.subjectKey(subject)
        let matches = lessons.sorted { $0.key < $1.key }.map { $0.value }.filter { Timetable.subjectKey($0.subject) == name }
        return matches.first { !$0.room.isEmpty || !$0.teacher.isEmpty } ?? matches.first
    }

    func colour(for subject: String) -> Int {
        let name = Timetable.subjectKey(subject)
        if let chosen = subjectColours[name] {
            return chosen
        }
        // Not saved yet (you're still typing): a steady guess from the name.
        return name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Timetable.colourCount
    }

    mutating func setColour(_ colour: Int, for subject: String) {
        let name = Timetable.subjectKey(subject)
        guard !name.isEmpty else { return }
        subjectColours[name] = ((colour % Timetable.colourCount) + Timetable.colourCount) % Timetable.colourCount
    }

    /// The colour fewest subjects have.
    private func freshColour() -> Int {
        let inUse = Set(lessons.values.map { Timetable.subjectKey($0.subject) })
        var counts = Array(repeating: 0, count: Timetable.colourCount)
        for (name, colour) in subjectColours where inUse.contains(name) && counts.indices.contains(colour) {
            counts[colour] += 1
        }
        let fewest = counts.min() ?? 0
        return counts.firstIndex(of: fewest) ?? 0
    }

    mutating func clearLessons() {
        lessons = [:]
        subjectColours = [:]
    }

    // MARK: The school day

    /// A new period at the end of the school day, an hour long (the hour blocks after school
    /// move along).
    @discardableResult
    mutating func addPeriod() -> UUID {
        let start = periods.last?.end ?? 9 * 60
        let end = min(start + 60, 24 * 60 - 1)
        let number = periods.filter { !$0.isBreak }.count + 1
        let period = Period(id: UUID(), name: "Period \(number)", start: min(start, end - 1), end: end, isBreak: false)
        periods.append(period)
        sortPeriods()
        return period.id
    }

    /// Saves a period's new name, times or kind. Times that end before they start are refused,
    /// and so are hour blocks, which follow the school day.
    @discardableResult
    mutating func updatePeriod(_ period: Period) -> Bool {
        guard period.end > period.start, (0..<24 * 60).contains(period.start), period.end <= 24 * 60,
              let index = periods.firstIndex(where: { $0.id == period.id }) else { return false }
        var saved = period
        saved.isActivity = false
        saved.name = period.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty {
            saved.name = periods[index].name
        }
        periods[index] = saved
        sortPeriods()
        return true
    }

    /// Takes a period out of the school day, with the lessons in it.
    mutating func removePeriod(_ id: UUID) {
        guard periods.contains(where: { $0.id == id }) else { return }
        periods.removeAll { $0.id == id }
        let suffix = "-" + id.uuidString
        lessons = lessons.filter { !$0.key.hasSuffix(suffix) }
    }

    /// School as one block from 8 to 4 (what's in a block called School is kept).
    mutating func useSchoolBlock() {
        replaceSchool(with: Timetable.schoolBlock())
        fillSchool()
    }

    /// School as seven periods, recess and lunch, from 8 to 4. Lessons in a period of the same
    /// name are kept.
    mutating func useSchoolPeriods() {
        replaceSchool(with: Timetable.schoolPeriods())
    }

    /// New school periods; lessons move to the period with the same name, the rest go.
    private mutating func replaceSchool(with fresh: [Period]) {
        let old = periods
        var moved: [String: Lesson] = [:]
        for (key, lesson) in lessons {
            guard let period = old.first(where: { key.hasSuffix("-" + $0.id.uuidString) }) else {
                moved[key] = lesson // an hour block's
                continue
            }
            guard let match = fresh.first(where: { $0.name.lowercased() == period.name.lowercased() }) else { continue }
            moved[String(key.dropLast(period.id.uuidString.count)) + match.id.uuidString] = lesson
        }
        periods = fresh
        lessons = moved
        let inUse = Set(moved.values.map { Timetable.subjectKey($0.subject) })
        subjectColours = subjectColours.filter { inUse.contains($0.key) }
    }

    /// School is one block from 8 to 4, as a new timetable starts.
    var hasStandardSchoolDay: Bool { matches(Timetable.schoolBlock()) }

    /// School is the seven periods from 8 to 4.
    var hasStandardPeriods: Bool { matches(Timetable.schoolPeriods()) }

    private mutating func sortPeriods() {
        periods.sort { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    // MARK: Days and weeks

    static func monday(of date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start) // 1 = Sunday
        let sinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -sinceMonday, to: start) ?? start
    }

    /// 0 for Monday … 6 for Sunday.
    static func dayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// The date's column on the timetable, or nil on a day it doesn't show (the weekend,
    /// unless weekends are on).
    func column(of date: Date, calendar: Calendar = .current) -> Int? {
        let day = Timetable.dayIndex(of: date, calendar: calendar)
        return day < dayCount ? day : nil
    }

    /// Which week of the cycle a date falls in: 0 (A) or 1 (B). Always 0 for one week.
    func week(of date: Date, calendar: Calendar = .current) -> Int {
        guard twoWeeks else { return 0 }
        let from = Timetable.monday(of: weekA, calendar: calendar)
        let to = Timetable.monday(of: date, calendar: calendar)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        let weeks = Int((Double(days) / 7).rounded(.down))
        return ((weeks % 2) + 2) % 2
    }

    /// Says which week this one is, A or B.
    mutating func setThisWeek(_ week: Int, now: Date = Date(), calendar: Calendar = .current) {
        let monday = Timetable.monday(of: now, calendar: calendar)
        weekA = week == 1 ? (calendar.date(byAdding: .day, value: -7, to: monday) ?? monday) : monday
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// A day's rows with what's on in each.
    func day(_ day: Int, week: Int) -> [(period: Period, lesson: Lesson?)] {
        rows.map { period in
            (period: period, lesson: period.isBreak ? nil : lesson(at: Slot(week: week, day: day, period: period.id)))
        }
    }

    struct Moment: Equatable {
        let period: Period
        let lesson: Lesson?
        let day: Int
        let week: Int
    }

    /// What's on now: a class, a break, or an activity (an hour block with nothing in it
    /// doesn't count).
    func now(at date: Date = Date(), calendar: Calendar = .current) -> Moment? {
        guard let day = column(of: date, calendar: calendar) else { return nil }
        let minute = Timetable.minuteOfDay(date, calendar: calendar)
        let week = self.week(of: date, calendar: calendar)
        guard let period = rows.first(where: { $0.contains(minute) }) else { return nil }
        let lesson = period.isBreak ? nil : self.lesson(at: Slot(week: week, day: day, period: period.id))
        // An empty hour block, or anything empty at the weekend, isn't "on".
        if lesson == nil && (period.isActivity || day >= 5) { return nil }
        return Moment(period: period, lesson: lesson, day: day, week: week)
    }

    /// The next class or activity with something in it: later today, or on a coming day.
    func next(after date: Date = Date(), calendar: Calendar = .current) -> (moment: Moment, date: Date)? {
        let minute = Timetable.minuteOfDay(date, calendar: calendar)
        let rows = self.rows
        for offset in 0..<15 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let column = column(of: day, calendar: calendar) else { continue }
            let week = self.week(of: day, calendar: calendar)
            for period in rows where !period.isBreak && (offset > 0 || period.start > minute) {
                if let lesson = lesson(at: Slot(week: week, day: column, period: period.id)) {
                    let at = calendar.date(byAdding: .minute, value: period.start, to: day) ?? day
                    return (Moment(period: period, lesson: lesson, day: column, week: week), at)
                }
            }
        }
        return nil
    }

    /// "Monday (Week A): 8:00 am Maths in B12 with Ms Lee; 5:00 pm Soccer at Oval" for the assistant.
    func summary(of date: Date, calendar: Calendar = .current) -> String? {
        guard let column = column(of: date, calendar: calendar) else { return nil }
        let week = self.week(of: date, calendar: calendar)
        let entries = day(column, week: week).compactMap { entry -> String? in
            guard let lesson = entry.lesson, !lesson.subject.isEmpty else { return nil }
            var line = "\(ClockTime.long(entry.period.start)) \(lesson.subject)"
            if !lesson.room.isEmpty { line += (entry.period.isActivity ? " at " : " in ") + lesson.room }
            if !lesson.teacher.isEmpty { line += " with \(lesson.teacher)" }
            return line
        }
        guard !entries.isEmpty else { return nil }
        let name = Timetable.dayNames[column] + (twoWeeks ? " (\(Timetable.weekName(week)))" : "")
        return "\(name): " + entries.joined(separator: "; ")
    }
}

/// The timetable, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Timetable.json. It never leaves this Mac.
final class TimetableStore: ObservableObject {
    @Published private(set) var timetable: Timetable

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Timetable.json")
    }

    init(url: URL = TimetableStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode(Timetable.self, from: data) {
            timetable = saved
        } else {
            timetable = Timetable.standard()
        }
    }

    /// Changes the timetable and saves it shortly after.
    func change(_ edit: (inout Timetable) -> Void) {
        var changed = timetable
        edit(&changed)
        guard changed != timetable else { return }
        timetable = changed
        saveSoon()
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Writes the timetable to disk straight away (also on quit).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(timetable) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save the timetable: \(error.localizedDescription)")
        }
    }
}
