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

/// Your timetable: what's on each day, each class and activity at its own times (as many as
/// you like, any length), Monday to Friday or the whole week, over one week or two (Week A
/// and Week B). The school day's periods are kept as bell times: classes can be put on
/// them with a click, and breaks (recess, lunch) show as bands across the school days.
struct Timetable: Codable, Equatable {
    /// One of the school day's bell times: a period, or a break.
    struct Period: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        /// Minutes after midnight.
        var start: Int
        var end: Int
        /// Recess, lunch and the like: shown as a band across the school days.
        var isBreak: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, start, end, isBreak
        }

        init(id: UUID, name: String, start: Int, end: Int, isBreak: Bool) {
            self.id = id
            self.name = name
            self.start = start
            self.end = end
            self.isBreak = isBreak
        }

        var times: String { "\(ClockTime.short(start))–\(ClockTime.short(end))" }

        func contains(_ minute: Int) -> Bool { minute >= start && minute < end }
    }

    /// What a class or activity is: its subject, where and who with.
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

    /// A class or activity on one day of the week, at its own times.
    struct Event: Codable, Equatable, Identifiable {
        var id: UUID
        /// Week of the cycle: 0 = Week A (or every week, on a one-week timetable), 1 = Week B.
        var week: Int
        /// 0 = Monday … 6 = Sunday.
        var day: Int
        /// Minutes after midnight.
        var start: Int
        var end: Int
        var subject: String
        var room: String
        var teacher: String

        init(id: UUID = UUID(), week: Int = 0, day: Int, start: Int, end: Int, subject: String, room: String = "", teacher: String = "") {
            self.id = id
            self.week = week
            self.day = day
            self.start = start
            self.end = end
            self.subject = subject
            self.room = room
            self.teacher = teacher
        }

        var lesson: Lesson {
            get { Lesson(subject: subject, room: room, teacher: teacher) }
            set {
                subject = newValue.subject
                room = newValue.room
                teacher = newValue.teacher
            }
        }

        var isEmpty: Bool { lesson.isEmpty }
        var minutes: Int { end - start }
        var times: String { "\(ClockTime.short(start))–\(ClockTime.short(end))" }

        func contains(_ minute: Int) -> Bool { minute >= start && minute < end }
        func overlaps(_ from: Int, _ to: Int) -> Bool { start < to && end > from }
    }

    /// The school day's bell times (periods and breaks), in time order.
    private(set) var periods: [Period]
    /// Every class and activity.
    private(set) var events: [Event]
    /// Each subject's colour (lowercased name → place in the palette), so all its classes match.
    private(set) var subjectColours: [String: Int]
    /// A colour of your own for a subject (lowercased name → RGB, like 0x5E9EFF), picked
    /// instead of one from the palette.
    private(set) var customColours: [String: UInt32] = [:]
    var twoWeeks: Bool
    /// A Monday of a Week A.
    var weekA: Date
    /// Saturday and Sunday too, for weekend activities.
    var weekends: Bool
    /// The part of the day the timetable shows, on the hour: 6 am to 10 pm to start with.
    /// (It stretches to show anything you put outside it.)
    private(set) var dayStart: Int
    private(set) var dayEnd: Int
    /// The version of the timetable it was saved with. 3: classes at their own times.
    private(set) var layout: Int

    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let shortDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let colourCount = 8
    /// The palette subjects get their colours from: bright enough to read on black, distinct
    /// side by side.
    static let palette: [UInt32] = [0x5E9EFF, 0x3DD6A3, 0xFFB547, 0xFF6B6B, 0xB18CFF, 0xFF7AC6, 0x56CFE1, 0xA6D85A]
    /// The day runs from 6 am to 10 pm to start with.
    static let standardStart = 6 * 60
    static let standardEnd = 22 * 60
    static let currentLayout = 3
    static let schoolSubject = "School"
    /// The shortest a class can be, and how its times snap when it's dragged.
    static let shortest = 5
    static let snap = 5

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

    /// A new timetable: school as one block from 8 to 4 on weekdays, in a day shown from
    /// 6 am to 10 pm.
    static func standard(now: Date = Date(), calendar: Calendar = .current) -> Timetable {
        var table = Timetable(periods: schoolBlock(), events: [], subjectColours: [:], twoWeeks: false,
                              weekA: monday(of: now, calendar: calendar), weekends: false)
        table.fillSchool()
        return table
    }

    init(periods: [Period], events: [Event] = [], subjectColours: [String: Int] = [:], twoWeeks: Bool = false,
         weekA: Date, weekends: Bool = false, dayStart: Int = Timetable.standardStart, dayEnd: Int = Timetable.standardEnd) {
        self.periods = periods.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        self.events = []
        self.subjectColours = subjectColours
        self.twoWeeks = twoWeeks
        self.weekA = weekA
        self.weekends = weekends
        self.dayStart = Timetable.hourDown(dayStart)
        self.dayEnd = max(Timetable.hourUp(dayEnd), Timetable.hourDown(dayStart) + 60)
        self.layout = Timetable.currentLayout
        for event in events {
            add(event)
        }
    }

    // MARK: Saving, and older timetables

    private enum CodingKeys: String, CodingKey {
        case periods, events, subjectColours, customColours, twoWeeks, weekA, weekends, dayStart, dayEnd, layout
        // Before build 50: classes in slots, and hour blocks around school.
        case lessons, beforeSchool, afterSchool
    }

    /// A class as timetables before build 50 kept it: in a slot, perhaps with its own times.
    private struct OldLesson: Decodable {
        var subject: String
        var room: String?
        var teacher: String?
        var start: Int?
        var end: Int?
    }

    /// Reads a saved timetable. One from before build 50 had its classes in slots (a period,
    /// or an hour block before or after school): each becomes a class at its slot's times
    /// (or the times it had of its own), and the day shown is the one its rows covered.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let savedPeriods = try values.decode([Period].self, forKey: .periods)
        periods = savedPeriods.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        subjectColours = (try? values.decodeIfPresent([String: Int].self, forKey: .subjectColours)) ?? [:]
        customColours = ((try? values.decodeIfPresent([String: UInt32].self, forKey: .customColours)) ?? [:]).mapValues(SubjectColour.readable)
        twoWeeks = (try? values.decodeIfPresent(Bool.self, forKey: .twoWeeks)) ?? false
        weekA = try values.decode(Date.self, forKey: .weekA)
        weekends = (try? values.decodeIfPresent(Bool.self, forKey: .weekends)) ?? false
        layout = (try? values.decodeIfPresent(Int.self, forKey: .layout)) ?? 0
        dayStart = (try? values.decodeIfPresent(Int.self, forKey: .dayStart)) ?? Timetable.standardStart
        dayEnd = (try? values.decodeIfPresent(Int.self, forKey: .dayEnd)) ?? Timetable.standardEnd
        events = []
        if layout >= 3 {
            let saved = (try? values.decodeIfPresent([Event].self, forKey: .events)) ?? []
            events = saved.filter { Timetable.validTimes(start: $0.start, end: $0.end) && (0..<7).contains($0.day) }
        } else {
            let lessons = (try? values.decodeIfPresent([String: OldLesson].self, forKey: .lessons)) ?? [:]
            let before = (try? values.decodeIfPresent(Int.self, forKey: .beforeSchool)) ?? 2
            let after = (try? values.decodeIfPresent(Int.self, forKey: .afterSchool)) ?? 6
            upgrade(lessons: lessons, before: before, after: after)
            // The first builds' timetables had their hour blocks fill the day from 6 am to 10 pm.
            if layout < 2 {
                dayStart = Timetable.standardStart
                dayEnd = Timetable.standardEnd
            }
            layout = Timetable.currentLayout
        }
        dayStart = Timetable.hourDown(max(0, min(dayStart, 23 * 60)))
        dayEnd = max(Timetable.hourUp(min(dayEnd, 24 * 60)), dayStart + 60)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(periods, forKey: .periods)
        try values.encode(events, forKey: .events)
        try values.encode(subjectColours, forKey: .subjectColours)
        if !customColours.isEmpty {
            try values.encode(customColours, forKey: .customColours)
        }
        try values.encode(twoWeeks, forKey: .twoWeeks)
        try values.encode(weekA, forKey: .weekA)
        try values.encode(weekends, forKey: .weekends)
        try values.encode(dayStart, forKey: .dayStart)
        try values.encode(dayEnd, forKey: .dayEnd)
        try values.encode(layout, forKey: .layout)
    }

    /// The fixed ID of an hour block before or after school, as timetables before build 50
    /// kept them: 1 is the hour just before (or after) school, 2 the one before (after) that.
    static func blockID(before: Bool, number: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-4000-8000-%012X", before ? 0xB10C_BEF0 : 0xB10C_AF7E, number))!
    }

    /// Turns the slots of a timetable from before build 50 into classes at their times.
    private mutating func upgrade(lessons: [String: OldLesson], before: Int, after: Int) {
        let start = periods.first?.start ?? 8 * 60
        let end = periods.map { $0.end }.max() ?? 16 * 60
        // Where each slot was: the periods, and the hour blocks around them (all of them,
        // so that a class in a block that was hidden still has its times).
        var rows: [UUID: (start: Int, end: Int)] = [:]
        for period in periods where !period.isBreak {
            rows[period.id] = (period.start, period.end)
        }
        for number in 1...8 {
            rows[Timetable.blockID(before: true, number: number)] = (start - number * 60, start - number * 60 + 60)
            rows[Timetable.blockID(before: false, number: number)] = (end + (number - 1) * 60, end + number * 60)
        }
        for (key, old) in lessons.sorted(by: { $0.key < $1.key }) {
            let parts = key.split(separator: "-", maxSplits: 2).map(String.init)
            guard parts.count == 3, let week = Int(parts[0]), let day = Int(parts[1]), let id = UUID(uuidString: parts[2]),
                  let row = rows[id], (0..<7).contains(day), row.start >= 0, row.end <= 24 * 60 else { continue }
            var from = row.start
            var to = row.end
            if let own = old.start, let ownEnd = old.end, Timetable.validTimes(start: own, end: ownEnd) {
                from = own
                to = ownEnd
            }
            let event = Event(week: week == 1 ? 1 : 0, day: day, start: from, end: to, subject: old.subject,
                              room: old.room ?? "", teacher: old.teacher ?? "")
            guard !event.isEmpty else { continue }
            events.append(event)
        }
        // The day shown: what the hour blocks covered.
        dayStart = Timetable.hourDown(max(0, start - min(before, 8) * 60))
        dayEnd = Timetable.hourUp(min(24 * 60, end + min(after, 8) * 60))
        if dayEnd <= dayStart {
            dayStart = Timetable.standardStart
            dayEnd = Timetable.standardEnd
        }
    }

    // MARK: The day shown

    static func hourDown(_ minute: Int) -> Int { max(0, minute / 60 * 60) }
    static func hourUp(_ minute: Int) -> Int { min(24 * 60, (minute + 59) / 60 * 60) }

    /// Chooses the part of the day shown, on the hour (it's never less than an hour).
    mutating func setDay(start: Int? = nil, end: Int? = nil) {
        if let start = start {
            dayStart = Timetable.hourDown(max(0, min(start, 23 * 60)))
        }
        if let end = end {
            dayEnd = Timetable.hourUp(max(60, min(end, 24 * 60)))
        }
        if dayEnd <= dayStart {
            if end != nil {
                dayStart = dayEnd - 60
            } else {
                dayEnd = dayStart + 60
            }
        }
    }

    /// What the timetable shows: the day you chose, stretched to take in every class (and
    /// the school day).
    var shownStart: Int {
        Timetable.hourDown(([dayStart, schoolStart] + events.map { $0.start }).min() ?? dayStart)
    }

    var shownEnd: Int {
        Timetable.hourUp(([dayEnd, schoolEnd] + events.map { $0.end }).max() ?? dayEnd)
    }

    // MARK: Classes

    /// Whether times make sense for a class: in the day, and at least five minutes long.
    static func validTimes(start: Int, end: Int) -> Bool {
        start >= 0 && end <= 24 * 60 && end - start >= shortest
    }

    /// The week a class is kept in: Week B only on a two-week timetable.
    private func weekKey(_ week: Int) -> Int { twoWeeks && week == 1 ? 1 : 0 }

    var isEmpty: Bool { events.isEmpty }

    func event(_ id: UUID?) -> Event? {
        guard let id = id else { return nil }
        return events.first { $0.id == id }
    }

    /// A day's classes and activities in the order they happen, for the week showing.
    func events(day: Int, week: Int) -> [Event] {
        let wanted = weekKey(week)
        return events.filter { $0.day == day && $0.week == wanted }
            .sorted { ($0.start, $0.end, $0.subject) < ($1.start, $1.end, $1.subject) }
    }

    /// Adds a class. Refused (nil) if its times or day make no sense. A new subject gets its
    /// own colour.
    @discardableResult
    mutating func add(_ event: Event) -> Event? {
        guard Timetable.validTimes(start: event.start, end: event.end), (0..<7).contains(event.day) else { return nil }
        var added = event
        added.week = weekKey(event.week)
        events.append(added)
        colourNew(added.subject)
        return added
    }

    /// A new class on a day, at the times given. (nil if they make no sense.)
    @discardableResult
    mutating func addEvent(day: Int, week: Int = 0, start: Int, end: Int, lesson: Lesson = Lesson(subject: "")) -> Event? {
        add(Event(week: week, day: day, start: start, end: end, subject: lesson.subject, room: lesson.room, teacher: lesson.teacher))
    }

    /// Saves a class as changed, as typed so far (spaces are trimmed once you've finished,
    /// by `tidy()`). Refused if its times or day make no sense.
    @discardableResult
    mutating func update(_ event: Event) -> Bool {
        guard Timetable.validTimes(start: event.start, end: event.end), (0..<7).contains(event.day),
              let index = events.firstIndex(where: { $0.id == event.id }) else { return false }
        var saved = event
        saved.week = weekKey(event.week)
        events[index] = saved
        colourNew(saved.subject)
        return true
    }

    /// Changes one class, if it's there.
    @discardableResult
    mutating func change(_ id: UUID, _ edit: (inout Event) -> Void) -> Bool {
        guard var event = event(id) else { return false }
        edit(&event)
        return update(event)
    }

    mutating func removeEvent(_ id: UUID) {
        events.removeAll { $0.id == id }
    }

    /// Moves a class to another day and start, keeping how long it is. It stays inside the
    /// day (and on a day the timetable has).
    @discardableResult
    mutating func move(_ id: UUID, day: Int, start: Int) -> Bool {
        guard let event = event(id) else { return false }
        let length = event.minutes
        let from = max(0, min(start, 24 * 60 - length))
        let column = max(0, min(day, dayCount - 1))
        return change(id) { moved in
            moved.day = column
            moved.start = from
            moved.end = from + length
        }
    }

    /// Changes when a class ends (it's at least five minutes long, and ends by midnight).
    @discardableResult
    mutating func resize(_ id: UUID, end: Int) -> Bool {
        guard let event = event(id) else { return false }
        let to = max(event.start + Timetable.shortest, min(end, 24 * 60))
        return change(id) { $0.end = to }
    }

    /// The same class on other days: the same subject at the same times in the same week.
    func twins(of id: UUID) -> [Event] {
        guard let event = event(id) else { return [] }
        let name = Timetable.subjectKey(event.subject)
        return events.filter { other in
            other.id != id && other.week == event.week && other.start == event.start && other.end == event.end
                && Timetable.subjectKey(other.subject) == name
        }
    }

    /// The days a class is on: its own, and those its twins are on.
    func days(of id: UUID) -> Set<Int> {
        guard let event = event(id) else { return [] }
        return Set([event.day] + twins(of: id).map { $0.day })
    }

    /// Puts the same class on another day too, or takes it off that day. (Its own day
    /// can't be taken off this way.)
    mutating func repeatOn(_ id: UUID, day: Int, _ on: Bool) {
        guard let event = event(id), day != event.day, (0..<7).contains(day) else { return }
        let there = twins(of: id).filter { $0.day == day }
        if on {
            guard there.isEmpty else { return }
            add(Event(week: event.week, day: day, start: event.start, end: event.end, subject: event.subject, room: event.room, teacher: event.teacher))
        } else {
            let gone = Set(there.map { $0.id })
            events.removeAll { gone.contains($0.id) }
        }
    }

    /// Times for a new class put at a minute of a day: the period it falls in on a school
    /// day, or else an hour from that quarter hour.
    func newTimes(day: Int, at minute: Int) -> (start: Int, end: Int) {
        if day < 5, let period = periods.first(where: { !$0.isBreak && $0.contains(minute) }), !schoolIsOneBlock {
            return (period.start, period.end)
        }
        let start = max(0, min(minute / 15 * 15, 24 * 60 - 60))
        return (start, start + 60)
    }

    /// A subject's name for matching: "  maths " and "Maths" are the same subject.
    static func subjectKey(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private mutating func colourNew(_ subject: String) {
        let name = Timetable.subjectKey(subject)
        if !name.isEmpty && subjectColours[name] == nil {
            subjectColours[name] = freshColour()
        }
    }

    /// After editing: spaces trimmed, classes left blank gone, and colours kept only for
    /// subjects still on the timetable.
    mutating func tidy() {
        events = events.compactMap { event in
            var clean = event
            clean.subject = event.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            clean.room = event.room.trimmingCharacters(in: .whitespacesAndNewlines)
            clean.teacher = event.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        let inUse = Set(events.map { Timetable.subjectKey($0.subject) })
        subjectColours = subjectColours.filter { inUse.contains($0.key) }
        customColours = customColours.filter { inUse.contains($0.key) }
    }

    /// Every subject (and activity) on the timetable, A to Z, as you first typed it.
    var subjects: [String] {
        var seen: [String: String] = [:]
        for event in events {
            let subject = event.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { continue }
            let name = subject.lowercased()
            if seen[name] == nil || subject < seen[name]! {
                seen[name] = subject
            }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Your classes and activities, without the "School" block: what homework can be for.
    var classes: [String] {
        subjects.filter { Timetable.subjectKey($0) != Timetable.subjectKey(Timetable.schoolSubject) }
    }

    /// The room and teacher another class of this subject has, to fill in for you.
    func usual(for subject: String) -> Lesson? {
        let name = Timetable.subjectKey(subject)
        let matches = events.sorted { ($0.week, $0.day, $0.start) < ($1.week, $1.day, $1.start) }
            .filter { Timetable.subjectKey($0.subject) == name }.map { $0.lesson }
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

    /// A colour from the palette, for every class of the subject (and no colour of your own).
    mutating func setColour(_ colour: Int, for subject: String) {
        let name = Timetable.subjectKey(subject)
        guard !name.isEmpty else { return }
        subjectColours[name] = ((colour % Timetable.colourCount) + Timetable.colourCount) % Timetable.colourCount
        customColours[name] = nil
    }

    /// The colour you picked for a subject yourself, if you did.
    func customColour(for subject: String) -> UInt32? {
        customColours[Timetable.subjectKey(subject)]
    }

    /// Any colour for every class of a subject. One too dark to read on black is lifted.
    mutating func setCustomColour(_ rgb: UInt32, for subject: String) {
        let name = Timetable.subjectKey(subject)
        guard !name.isEmpty else { return }
        customColours[name] = SubjectColour.readable(rgb)
    }

    /// The colour a subject's classes are drawn in: yours if you picked one, otherwise its
    /// palette colour.
    func rgb(for subject: String) -> UInt32 {
        customColour(for: subject) ?? Timetable.palette[colour(for: subject) % Timetable.palette.count]
    }

    /// The colour fewest subjects have.
    private func freshColour() -> Int {
        let inUse = Set(events.map { Timetable.subjectKey($0.subject) })
        var counts = Array(repeating: 0, count: Timetable.colourCount)
        for (name, colour) in subjectColours where inUse.contains(name) && counts.indices.contains(colour) {
            counts[colour] += 1
        }
        let fewest = counts.min() ?? 0
        return counts.firstIndex(of: fewest) ?? 0
    }

    /// Clears every class, for a new term. The bell times stay.
    mutating func clearLessons() {
        events = []
        subjectColours = [:]
        customColours = [:]
    }

    /// Why times typed for a class can't be saved, or nil if they can.
    static func timesProblem(start: String, end: String) -> String? {
        guard let from = ClockTime.parse(start), let to = ClockTime.parse(end) else {
            return "Type times like 5:15 pm or 17:15."
        }
        if to <= from { return "It needs to end after it starts." }
        if to - from < shortest { return "It needs to be at least \(shortest) minutes long." }
        return nil
    }

    /// How classes that overlap on a day sit side by side: for each, its lane and how many
    /// lanes its cluster of overlapping classes has.
    static func lanes(_ events: [Event]) -> [UUID: (lane: Int, of: Int)] {
        let sorted = events.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [UUID: (lane: Int, of: Int)] = [:]
        var cluster: [(id: UUID, lane: Int)] = []
        var laneEnds: [Int] = []
        var clusterEnd = -1
        func finish() {
            for member in cluster {
                result[member.id] = (member.lane, max(1, laneEnds.count))
            }
            cluster = []
            laneEnds = []
        }
        for event in sorted {
            if event.start >= clusterEnd {
                finish()
            }
            if let free = laneEnds.firstIndex(where: { $0 <= event.start }) {
                laneEnds[free] = event.end
                cluster.append((event.id, free))
            } else {
                laneEnds.append(event.end)
                cluster.append((event.id, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, event.end)
        }
        finish()
        return result
    }

    // MARK: The school day (bell times)

    /// School is one block (rather than periods).
    var schoolIsOneBlock: Bool { periods.count == 1 }

    /// When school starts and ends: the first and last period.
    var schoolStart: Int { periods.first?.start ?? 8 * 60 }
    var schoolEnd: Int { periods.map { $0.end }.max() ?? 16 * 60 }

    func period(_ id: UUID?) -> Period? {
        guard let id = id else { return nil }
        return periods.first { $0.id == id }
    }

    /// The school day's breaks.
    var breaks: [Period] { periods.filter { $0.isBreak } }

    /// "School" from the school block's start to its end on every weekday that doesn't
    /// already have a class at exactly those times.
    mutating func fillSchool() {
        guard schoolIsOneBlock, let school = periods.first else { return }
        for week in 0...1 {
            for day in 0..<5 where !events.contains(where: { $0.week == week && $0.day == day && $0.start == school.start && $0.end == school.end }) {
                events.append(Event(week: week, day: day, start: school.start, end: school.end, subject: Timetable.schoolSubject))
            }
        }
        colourNew(Timetable.schoolSubject)
    }

    /// A new period at the end of the school day, an hour long.
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

    /// Saves a period's new name, times or kind. Times that end before they start are
    /// refused. Classes that were on the period's old times move with it.
    @discardableResult
    mutating func updatePeriod(_ period: Period) -> Bool {
        guard period.end > period.start, (0..<24 * 60).contains(period.start), period.end <= 24 * 60,
              let index = periods.firstIndex(where: { $0.id == period.id }) else { return false }
        let old = periods[index]
        var saved = period
        saved.name = period.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty {
            saved.name = old.name
        }
        periods[index] = saved
        sortPeriods()
        if old.start != saved.start || old.end != saved.end {
            for i in events.indices where events[i].start == old.start && events[i].end == old.end {
                events[i].start = saved.start
                events[i].end = saved.end
            }
        }
        return true
    }

    /// Takes a period out of the school day, with the classes on its times.
    mutating func removePeriod(_ id: UUID) {
        guard let period = period(id) else { return }
        periods.removeAll { $0.id == id }
        events.removeAll { $0.start == period.start && $0.end == period.end }
    }

    /// School as one block from 8 to 4. Classes on the old periods' times go, unless a
    /// period was called School.
    mutating func useSchoolBlock() {
        replaceSchool(with: Timetable.schoolBlock())
        fillSchool()
    }

    /// School as seven periods, recess and lunch, from 8 to 4. Classes on a period's times
    /// move to the new period of the same name; the rest of the old school day goes.
    mutating func useSchoolPeriods() {
        replaceSchool(with: Timetable.schoolPeriods())
    }

    /// New bell times. Classes on an old period's times move to the new period with the
    /// same name, or go; everything else (activities) stays.
    private mutating func replaceSchool(with fresh: [Period]) {
        let old = periods
        var kept: [Event] = []
        for event in events {
            guard let period = old.first(where: { $0.start == event.start && $0.end == event.end }) else {
                kept.append(event)
                continue
            }
            guard let match = fresh.first(where: { $0.name.lowercased() == period.name.lowercased() }) else { continue }
            var moved = event
            moved.start = match.start
            moved.end = match.end
            kept.append(moved)
        }
        periods = fresh.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        events = kept
        let inUse = Set(kept.map { Timetable.subjectKey($0.subject) })
        subjectColours = subjectColours.filter { inUse.contains($0.key) }
        customColours = customColours.filter { inUse.contains($0.key) }
    }

    private func matches(_ day: [Period]) -> Bool {
        periods.count == day.count && zip(periods, day).allSatisfy { period, other in
            period.name == other.name && period.start == other.start && period.end == other.end && period.isBreak == other.isBreak
        }
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

    // MARK: Now and next

    /// What's on at a moment: a class, or on a school day a break or free time.
    struct Moment: Equatable {
        /// The class or activity that's on (nil for a break or free time).
        let event: Event?
        /// The bell time it falls in, if any: the break, or the period that's free.
        let period: Period?
        let day: Int
        let week: Int
        /// When it runs. Free time runs until its period ends, or a class starts.
        let start: Int
        let end: Int

        var lesson: Lesson? { event?.lesson }
        var isBreak: Bool { event == nil && period?.isBreak == true }
        /// What it's called: the class, the break, or "Free".
        var name: String {
            if let event = event {
                let subject = event.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                return subject.isEmpty ? "Class" : subject
            }
            return isBreak ? (period?.name ?? "Break") : "Free"
        }
    }

    /// What's on now: a class or activity (of two that overlap, the one that started last),
    /// or on a school day during school hours a break or free time. Nothing late at night,
    /// in a gap after school, or at the weekend with nothing on.
    func now(at date: Date = Date(), calendar: Calendar = .current) -> Moment? {
        guard let day = column(of: date, calendar: calendar) else { return nil }
        let minute = Timetable.minuteOfDay(date, calendar: calendar)
        let week = self.week(of: date, calendar: calendar)
        let today = events(day: day, week: week)
        if let on = today.last(where: { $0.contains(minute) }) {
            return Moment(event: on, period: periods.first { $0.contains(minute) }, day: day, week: week, start: on.start, end: on.end)
        }
        guard day < 5, let period = periods.first(where: { $0.contains(minute) }) else { return nil }
        let until = today.first(where: { $0.start > minute && $0.start < period.end })?.start ?? period.end
        return Moment(event: nil, period: period, day: day, week: week, start: period.start, end: until)
    }

    /// The next class or activity: later today, or on a coming day.
    func next(after date: Date = Date(), calendar: Calendar = .current) -> (moment: Moment, date: Date)? {
        let minute = Timetable.minuteOfDay(date, calendar: calendar)
        for offset in 0..<15 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let column = column(of: day, calendar: calendar) else { continue }
            let week = self.week(of: day, calendar: calendar)
            if let event = events(day: column, week: week).first(where: { offset > 0 || $0.start > minute }) {
                let at = calendar.date(byAdding: .minute, value: event.start, to: day) ?? day
                return (Moment(event: event, period: nil, day: column, week: week, start: event.start, end: event.end), at)
            }
        }
        return nil
    }

    /// "Monday (Week A): 8:00 am to 9:00 am Maths in B12 with Ms Lee; 5:15 pm to 6:00 pm
    /// Piano at Studio" for the assistant. (Outside school hours a place is "at", not "in".)
    func summary(of date: Date, calendar: Calendar = .current) -> String? {
        guard let column = column(of: date, calendar: calendar) else { return nil }
        let week = self.week(of: date, calendar: calendar)
        let lines = events(day: column, week: week).compactMap { event -> String? in
            let subject = event.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { return nil }
            var line = "\(ClockTime.long(event.start)) to \(ClockTime.long(event.end)) \(subject)"
            let inSchool = column < 5 && event.start >= schoolStart && event.start < schoolEnd
            if !event.room.isEmpty { line += (inSchool ? " in " : " at ") + event.room }
            if !event.teacher.isEmpty { line += " with \(event.teacher)" }
            return line
        }
        guard !lines.isEmpty else { return nil }
        let name = Timetable.dayNames[column] + (twoWeeks ? " (\(Timetable.weekName(week)))" : "")
        return "\(name): " + lines.joined(separator: "; ")
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

/// Colours as the picker works with them: hue, strength and brightness, each 0 to 1, and
/// hex codes like #5E9EFF.
enum SubjectColour {
    /// Colours are kept at least this bright, so classes stay readable on the notch's black.
    static let darkest = 0.3

    static func rgb(hue: Double, saturation: Double, brightness: Double) -> UInt32 {
        let h = (hue - hue.rounded(.down)) * 6
        let s = min(max(saturation, 0), 1)
        let v = min(max(brightness, 0), 1)
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch sector {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        func byte(_ x: Double) -> UInt32 { UInt32((x * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    static func hsb(_ rgb: UInt32) -> (hue: Double, saturation: Double, brightness: Double) {
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let most = max(r, g, b), least = min(r, g, b), range = most - least
        var hue = 0.0
        if range > 0 {
            if most == r {
                hue = ((g - b) / range).truncatingRemainder(dividingBy: 6)
            } else if most == g {
                hue = (b - r) / range + 2
            } else {
                hue = (r - g) / range + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, most == 0 ? 0 : range / most, most)
    }

    /// The colour, at least bright enough to read on black.
    static func readable(_ rgb: UInt32) -> UInt32 {
        let colour = rgb & 0xFFFFFF
        let (h, s, b) = hsb(colour)
        return b >= darkest ? colour : self.rgb(hue: h, saturation: s, brightness: darkest)
    }

    /// "#5E9EFF".
    static func text(_ rgb: UInt32) -> String {
        "#" + String(format: "%06X", rgb & 0xFFFFFF)
    }

    /// A typed hex code: "#5e9eff", "5E9EFF" or "#5AF". Nil if it isn't one.
    static func parse(_ typed: String) -> UInt32? {
        var hex = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex, radix: 16)
    }
}
