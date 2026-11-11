import Foundation

/// A stretch of homework or revision, fitted into free time.
struct StudySession: Equatable, Identifiable {
    var title: String
    var subject: String
    var start: Date
    var minutes: Int
    /// The homework it's for, or the exam it's revision for.
    var taskID: UUID?
    var examID: UUID?
    /// It couldn't fit before it's due.
    var late = false

    var id: String { "\((taskID ?? examID)?.uuidString ?? title)-\(Int(start.timeIntervalSince1970))" }
    var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    var isRevision: Bool { examID != nil }
}

/// Fits your homework and exam revision into the free hours on your timetable: after school
/// on school days, through the day at weekends. Whatever's due soonest goes first, a little
/// each day rather than all at once, and revision lands on the days just before each exam.
enum StudyPlanner {
    /// How far ahead to plan.
    static let days = 14
    /// How much study to plan in a day unless Settings says otherwise.
    static let standardDaily = 120
    /// Weekend study hours.
    static let weekendStart = 9 * 60
    static let weekendEnd = 18 * 60
    /// Nothing is planned to end after this, on any night.
    static let latest = 21 * 60 + 30
    /// A stretch shorter than this isn't worth sitting down for (unless it finishes the job).
    static let shortest = 15
    /// Revision for one exam in one day.
    static let revisionADay = 60

    /// A free stretch of a day, with how much of it is taken so far.
    private struct Slot {
        let day: Int
        let start: Date
        let minutes: Int
        var used = 0

        var free: Int { minutes - used }
        var next: Date { start.addingTimeInterval(TimeInterval(used * 60)) }
        var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    /// The free stretches of the coming days, in order. `day` counts from today.
    private static func slots(timetable: Timetable, now: Date, calendar: Calendar) -> [Slot] {
        var slots: [Slot] = []
        let today = calendar.startOfDay(for: now)
        let rows = timetable.rows
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayIndex = Timetable.dayIndex(of: date, calendar: calendar)
            let week = timetable.week(of: date, calendar: calendar)
            func busy(_ from: Int, _ to: Int) -> Bool {
                rows.contains { row in
                    guard row.start < to, row.end > from else { return false }
                    if row.isBreak { return dayIndex < 5 && !row.isActivity }
                    return timetable.lesson(at: Timetable.Slot(week: week, day: dayIndex, period: row.id)) != nil
                }
            }
            // School days: from when school ends. Weekends: through the day.
            var hour = dayIndex < 5 ? timetable.schoolEnd : weekendStart
            let end = dayIndex < 5 ? latest : weekendEnd
            while hour + 30 <= end {
                let finish = min(hour + 60, end)
                defer { hour += 60 }
                guard !busy(hour, finish), let start = calendar.date(byAdding: .minute, value: hour, to: date) else { continue }
                var from = start
                var length = finish - hour
                if offset == 0 {
                    // What's left of today, starting on the next five minutes.
                    let minute = Timetable.minuteOfDay(now, calendar: calendar)
                    if minute >= finish { continue }
                    if minute > hour {
                        let rounded = ((minute + 4) / 5) * 5
                        length = finish - rounded
                        guard length >= shortest + 5, let later = calendar.date(byAdding: .minute, value: rounded, to: date) else { continue }
                        from = later
                    }
                }
                slots.append(Slot(day: offset, start: from, minutes: length))
            }
        }
        return slots
    }

    /// Homework and revision for the coming two weeks, in the order to do it.
    /// - Parameter daily: minutes of study to plan in a day; 0 for as much as fits.
    static func plan(tasks: [PlannerTask], exams: [Exam], timetable: Timetable, now: Date = Date(),
                     calendar: Calendar = .current, daily: Int = StudyPlanner.standardDaily) -> [StudySession] {
        var slots = self.slots(timetable: timetable, now: now, calendar: calendar)
        var usedByDay: [Int: Int] = [:]
        var sessions: [StudySession] = []

        /// Takes up to `minutes` from free time that `allows` it, earliest first. Returns what was left over.
        func take(_ minutes: Int, title: String, subject: String, taskID: UUID?, examID: UUID?, late: Bool = false,
                  dayLimit: Int?, itemADay: Int? = nil, backwards: Bool = false, allows: (Slot) -> Bool) -> Int {
            var left = minutes
            var takenByDay: [Int: Int] = [:]
            // Backwards (revision): the last days first, but the earliest free time within a day.
            let indices = backwards
                ? slots.indices.sorted { slots[$0].day != slots[$1].day ? slots[$0].day > slots[$1].day : $0 < $1 }
                : Array(slots.indices)
            for index in indices where left > 0 {
                let slot = slots[index]
                guard slot.free > 0, allows(slot) else { continue }
                var room = slot.free
                if let limit = dayLimit, limit > 0 {
                    room = min(room, limit - (usedByDay[slot.day] ?? 0))
                }
                if let limit = itemADay {
                    room = min(room, limit - (takenByDay[slot.day] ?? 0))
                }
                let amount = min(left, room)
                guard amount > 0, amount >= shortest || amount == left else { continue }
                sessions.append(StudySession(title: title, subject: subject, start: slot.next, minutes: amount,
                                             taskID: taskID, examID: examID, late: late))
                slots[index].used += amount
                usedByDay[slot.day, default: 0] += amount
                takenByDay[slot.day, default: 0] += amount
                left -= amount
            }
            return left
        }

        // Homework: what's due soonest first, each as early as it fits.
        let schoolStart = timetable.schoolStart
        let dated = tasks.filter { !$0.done && $0.due != nil }.sorted { a, b in
            let x = a.deadline(schoolStart: schoolStart, calendar: calendar) ?? .distantFuture
            let y = b.deadline(schoolStart: schoolStart, calendar: calendar) ?? .distantFuture
            return x != y ? x < y : a.added < b.added
        }
        for task in dated {
            guard let deadline = task.deadline(schoolStart: schoolStart, calendar: calendar) else { continue }
            let inTime: (Slot) -> Bool = { $0.end <= deadline }
            // Within the day's limit if it can be; over it rather than late; late rather than never.
            var left = take(task.minutes, title: task.title, subject: task.subject, taskID: task.id, examID: nil,
                            dayLimit: daily, allows: inTime)
            if left > 0 {
                left = take(left, title: task.title, subject: task.subject, taskID: task.id, examID: nil,
                            dayLimit: nil, allows: inTime)
            }
            if left > 0 {
                left = take(left, title: task.title, subject: task.subject, taskID: task.id, examID: nil, late: true,
                            dayLimit: daily, allows: { _ in true })
            }
            if left > 0 {
                _ = take(left, title: task.title, subject: task.subject, taskID: task.id, examID: nil, late: true,
                         dayLimit: nil, allows: { _ in true })
            }
        }

        // Revision: an hour a day on the days before each exam, the soonest exam first.
        let coming = exams.filter { $0.studyMinutes > 0 && !$0.isPast(now: now, calendar: calendar) }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.title < $1.title }
        for exam in coming {
            let examDay = calendar.startOfDay(for: exam.date)
            // Revision starts a few days out: a day for each hour of it, and one to spare.
            let window = max(3, (exam.studyMinutes + revisionADay - 1) / revisionADay + 1)
            let opens = calendar.date(byAdding: .day, value: -window, to: examDay) ?? examDay
            let before: (Slot) -> Bool = { slot in
                slot.start >= opens && (exam.hasTime ? slot.end <= exam.date : slot.start < examDay)
            }
            let title = "Revise: \(exam.name)"
            let left = take(exam.studyMinutes, title: title, subject: exam.subject, taskID: nil, examID: exam.id,
                            dayLimit: daily, itemADay: revisionADay, backwards: true, allows: before)
            if left > 0 {
                _ = take(left, title: title, subject: exam.subject, taskID: nil, examID: exam.id,
                         dayLimit: nil, itemADay: revisionADay, backwards: true, allows: before)
            }
        }

        return merged(sessions.sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title })
    }

    /// Back-to-back stretches of the same work become one.
    private static func merged(_ sessions: [StudySession]) -> [StudySession] {
        var result: [StudySession] = []
        for session in sessions {
            if let last = result.last, last.taskID == session.taskID, last.examID == session.examID,
               last.late == session.late, abs(last.end.timeIntervalSince(session.start)) < 1 {
                result[result.count - 1].minutes += session.minutes
            } else {
                result.append(session)
            }
        }
        return result
    }

    /// The plan grouped by day, for showing: today first.
    static func byDay(_ sessions: [StudySession], calendar: Calendar = .current) -> [(day: Date, sessions: [StudySession])] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { (day: $0, sessions: grouped[$0] ?? []) }
    }

    /// Homework that won't fit before it's due.
    static func late(_ sessions: [StudySession]) -> Set<UUID> {
        Set(sessions.filter { $0.late }.compactMap { $0.taskID })
    }
}
