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

    /// 530 → "8:50 am", 790 → "1:10 pm".
    static func long(_ minutes: Int) -> String {
        short(minutes) + (minutes / 60 % 24 < 12 ? " am" : " pm")
    }
}

/// Your school timetable: the periods of the day (classes and breaks), and what's on in
/// each one, Monday to Friday. It can run over two weeks (Week A and Week B).
struct Timetable: Codable, Equatable {
    struct Period: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        /// Minutes after midnight.
        var start: Int
        var end: Int
        /// Recess, lunch and the like: shown as a slim row across every day.
        var isBreak: Bool

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

    /// Where a lesson sits: week of the cycle (0 = A, 1 = B), weekday (0 = Monday), period.
    struct Slot: Hashable {
        var week: Int
        var day: Int
        var period: UUID
    }

    /// Oldest first, always in time order.
    private(set) var periods: [Period]
    /// Keyed "week-day-period".
    private(set) var lessons: [String: Lesson]
    /// Each subject's colour (lowercased name → place in the palette), so all its lessons match.
    private(set) var subjectColours: [String: Int]
    var twoWeeks: Bool
    /// A Monday of a Week A.
    var weekA: Date

    static let days = 5
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    static let shortDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    static let colourCount = 8

    static func weekName(_ week: Int) -> String { week == 1 ? "Week B" : "Week A" }

    /// A usual NSW high school day to start from: five periods, recess and lunch.
    static func standard(now: Date = Date(), calendar: Calendar = .current) -> Timetable {
        func period(_ name: String, _ start: String, _ end: String, isBreak: Bool = false) -> Period {
            Period(id: UUID(), name: name, start: ClockTime.parse(start) ?? 0, end: ClockTime.parse(end) ?? 0, isBreak: isBreak)
        }
        return Timetable(periods: [
            period("Period 1", "8:50", "9:50"),
            period("Period 2", "9:50", "10:50"),
            period("Recess", "10:50", "11:10", isBreak: true),
            period("Period 3", "11:10", "12:10"),
            period("Period 4", "12:10", "1:10"),
            period("Lunch", "1:10", "1:50", isBreak: true),
            period("Period 5", "1:50", "2:50"),
        ], lessons: [:], subjectColours: [:], twoWeeks: false, weekA: monday(of: now, calendar: calendar))
    }

    var isEmpty: Bool { lessons.isEmpty }

    func period(_ id: UUID?) -> Period? {
        guard let id = id else { return nil }
        return periods.first { $0.id == id }
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

    /// Every subject on the timetable, A to Z, as you first typed it.
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

    // MARK: Periods

    /// A new period after the last one, an hour long.
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

    /// Saves a period's new name, times or kind. Times that end before they start are refused.
    @discardableResult
    mutating func updatePeriod(_ period: Period) -> Bool {
        guard period.end > period.start, (0..<24 * 60).contains(period.start), period.end <= 24 * 60,
              let index = periods.firstIndex(where: { $0.id == period.id }) else { return false }
        var saved = period
        saved.name = period.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty {
            saved.name = periods[index].name
        }
        periods[index] = saved
        sortPeriods()
        return true
    }

    /// Takes a period out, with the lessons in it.
    mutating func removePeriod(_ id: UUID) {
        periods.removeAll { $0.id == id }
        let suffix = "-" + id.uuidString
        lessons = lessons.filter { !$0.key.hasSuffix(suffix) }
    }

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

    /// 0 for Monday … 4 for Friday; nil at the weekend.
    static func weekday(of date: Date, calendar: Calendar) -> Int? {
        let day = (calendar.component(.weekday, from: date) + 5) % 7
        return day < days ? day : nil
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

    /// A day's periods with what's on in each.
    func day(_ day: Int, week: Int) -> [(period: Period, lesson: Lesson?)] {
        periods.map { period in
            (period: period, lesson: period.isBreak ? nil : lesson(at: Slot(week: week, day: day, period: period.id)))
        }
    }

    struct Moment: Equatable {
        let period: Period
        let lesson: Lesson?
        let day: Int
        let week: Int
    }

    /// The period going on now (a class or a break), on a school day.
    func now(at date: Date = Date(), calendar: Calendar = .current) -> Moment? {
        guard let day = Timetable.weekday(of: date, calendar: calendar) else { return nil }
        let minute = Timetable.minuteOfDay(date, calendar: calendar)
        let week = self.week(of: date, calendar: calendar)
        guard let period = periods.first(where: { $0.contains(minute) }) else { return nil }
        let lesson = period.isBreak ? nil : self.lesson(at: Slot(week: week, day: day, period: period.id))
        return Moment(period: period, lesson: lesson, day: day, week: week)
    }

    /// The next class with something in it: later today, or on the next school day.
    func next(after date: Date = Date(), calendar: Calendar = .current) -> (moment: Moment, date: Date)? {
        let minute = Timetable.minuteOfDay(date, calendar: calendar)
        for offset in 0..<15 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let weekday = Timetable.weekday(of: day, calendar: calendar) else { continue }
            let week = self.week(of: day, calendar: calendar)
            for period in periods where !period.isBreak && (offset > 0 || period.start > minute) {
                if let lesson = lesson(at: Slot(week: week, day: weekday, period: period.id)) {
                    let at = calendar.date(byAdding: .minute, value: period.start, to: day) ?? day
                    return (Moment(period: period, lesson: lesson, day: weekday, week: week), at)
                }
            }
        }
        return nil
    }

    /// "Monday (Week A): 8:50 am Maths in B12 with Ms Lee; …" for the assistant.
    func summary(of date: Date, calendar: Calendar = .current) -> String? {
        guard let day = Timetable.weekday(of: date, calendar: calendar) else { return nil }
        let week = self.week(of: date, calendar: calendar)
        let classes = self.day(day, week: week).compactMap { entry -> String? in
            guard let lesson = entry.lesson, !lesson.subject.isEmpty else { return nil }
            var line = "\(ClockTime.long(entry.period.start)) \(lesson.subject)"
            if !lesson.room.isEmpty { line += " in \(lesson.room)" }
            if !lesson.teacher.isEmpty { line += " with \(lesson.teacher)" }
            return line
        }
        guard !classes.isEmpty else { return nil }
        let name = Timetable.dayNames[day] + (twoWeeks ? " (\(Timetable.weekName(week)))" : "")
        return "\(name): " + classes.joined(separator: "; ")
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
