import Foundation
#if canImport(Combine)
import Combine
#endif

extension Date {
    /// Now, to the second, so what's saved reads back exactly the same.
    static var toTheSecond: Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }
}

/// Where something in the planner came from.
enum PlannerSource: String, Codable {
    /// You typed it in.
    case typed
    /// A Google Classroom email (read on this Mac, no AI involved).
    case classroom
    /// The assistant added it because you asked.
    case assistant
    /// The assistant found it while looking through an email.
    case found
}

/// Something to do by a date: homework, an assignment, a form to hand in.
struct PlannerTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// The class or subject, e.g. "Maths". May be empty.
    var subject = ""
    /// When it's due; nil for no due date.
    var due: Date?
    /// False when it's just due that day, at no particular time.
    var hasTime = false
    /// How long you expect it to take, for fitting it into your week.
    var minutes = PlannerTask.standardMinutes
    var done = false
    var doneAt: Date?
    var notes = ""
    var source = PlannerSource.typed
    /// The email it came from, to open it again.
    var emailID: String?
    /// Where to open it: its page in Classroom, say.
    var link: URL?
    var added = Date.toTheSecond

    static let standardMinutes = 30

    private static let quickWords: Set<String> = ["form", "forms", "permission", "slip", "consent", "payment", "pay", "sign", "signed",
                                                  "bring", "return", "rsvp", "email", "ask"]
    private static let longWords: Set<String> = ["essay", "report", "project", "assignment", "assessment", "investigation", "portfolio",
                                                 "presentation", "speech", "draft", "research", "poster", "task", "prac"]
    private static let revisionWords: Set<String> = ["revise", "revision", "study", "practise", "practice"]

    /// A first guess at how long something takes, from its name: a form is quick, an essay
    /// isn't. You can change it; it's only for fitting things into your week.
    static func guessMinutes(for title: String) -> Int {
        let words = Set(title.lowercased().split(whereSeparator: { !$0.isLetter }).map { String($0) })
        if !words.isDisjoint(with: longWords) { return 90 }
        if !words.isDisjoint(with: revisionWords) { return 60 }
        if !words.isDisjoint(with: quickWords) { return 10 }
        return standardMinutes
    }

    /// When the work has to be finished by: the time it's due, or the start of the school
    /// day it's due on.
    func deadline(schoolStart: Int, calendar: Calendar = .current) -> Date? {
        guard let due = due else { return nil }
        if hasTime { return due }
        return calendar.date(byAdding: .minute, value: schoolStart, to: calendar.startOfDay(for: due))
    }

    /// Past its due date and not done. Something due today (no time given) isn't overdue until tomorrow.
    func isOverdue(now: Date, calendar: Calendar = .current) -> Bool {
        guard !done, let due = due else { return false }
        return hasTime ? due < now : DueText.days(until: due, now: now, calendar: calendar) < 0
    }
}

/// An exam, test or assessment day to count down to.
struct Exam: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var subject = ""
    var date: Date
    var hasTime = false
    /// Where it is, e.g. "Hall".
    var place = ""
    /// How much revision to fit in over the days before.
    var studyMinutes = Exam.standardStudy
    var notes = ""
    var source = PlannerSource.typed
    var emailID: String?
    var added = Date.toTheSecond

    static let standardStudy = 120

    /// What to call it in a line: "Maths: Yearly exam", or just the title if that already says the subject.
    var name: String {
        let subject = self.subject.trimmingCharacters(in: .whitespaces)
        if subject.isEmpty || title.lowercased().contains(subject.lowercased()) { return title }
        return "\(subject): \(title)"
    }

    /// Over, as of the end of its day.
    func isPast(now: Date, calendar: Calendar = .current) -> Bool {
        DueText.days(until: date, now: now, calendar: calendar) < 0
    }
}

/// Your homework and exams. Kept on this Mac.
struct Planner: Codable, Equatable {
    private(set) var tasks: [PlannerTask] = []
    private(set) var exams: [Exam] = []

    /// An email that's been looked through for things to do.
    struct Looked: Codable, Equatable {
        var at: Date
        /// Whether its whole text was there to read (not just Gmail's preview).
        var whole: Bool
        /// Whether the assistant has read it too.
        var byAssistant: Bool
    }

    /// Emails already looked through, so each is read once.
    private(set) var looked: [String: Looked] = [:]
    /// Things found in emails that you removed ("email|title"), so they aren't added again.
    private(set) var dismissed: Set<String> = []

    static let keepDoneFor: TimeInterval = 30 * 24 * 3600
    static let keepExamsFor: TimeInterval = 14 * 24 * 3600
    static let keepLooked = 4000

    enum CodingKeys: String, CodingKey {
        case tasks, exams, looked, dismissed
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decodeIfPresent([PlannerTask].self, forKey: .tasks) ?? []
        exams = try values.decodeIfPresent([Exam].self, forKey: .exams) ?? []
        looked = try values.decodeIfPresent([String: Looked].self, forKey: .looked) ?? [:]
        dismissed = try values.decodeIfPresent(Set<String>.self, forKey: .dismissed) ?? []
    }

    var isEmpty: Bool { tasks.isEmpty && exams.isEmpty }

    // MARK: Homework

    func task(_ id: UUID?) -> PlannerTask? {
        guard let id = id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// A new task; returns its ID.
    @discardableResult
    mutating func add(_ task: PlannerTask) -> UUID {
        tasks.append(task)
        return task.id
    }

    mutating func update(_ task: PlannerTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var changed = task
        changed.minutes = max(5, min(changed.minutes, 600))
        tasks[index] = changed
    }

    mutating func setDone(_ id: UUID, _ done: Bool, now: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].done != done else { return }
        tasks[index].done = done
        tasks[index].doneAt = done ? now : nil
    }

    /// Takes a task out. One that came from an email won't be picked up from it again.
    mutating func removeTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks.remove(at: index)
        if let email = task.emailID {
            dismissed.insert(Planner.key(email: email, title: task.title))
        }
    }

    /// Finished tasks, cleared away in one go.
    mutating func clearDone() {
        for task in tasks where task.done {
            removeTask(task.id)
        }
    }

    // MARK: Exams

    func exam(_ id: UUID?) -> Exam? {
        guard let id = id else { return nil }
        return exams.first { $0.id == id }
    }

    @discardableResult
    mutating func add(_ exam: Exam) -> UUID {
        exams.append(exam)
        return exam.id
    }

    mutating func update(_ exam: Exam) {
        guard let index = exams.firstIndex(where: { $0.id == exam.id }) else { return }
        var changed = exam
        changed.studyMinutes = max(0, min(changed.studyMinutes, 1200))
        exams[index] = changed
    }

    mutating func removeExam(_ id: UUID) {
        guard let index = exams.firstIndex(where: { $0.id == id }) else { return }
        let exam = exams.remove(at: index)
        if let email = exam.emailID {
            dismissed.insert(Planner.key(email: email, title: exam.title))
        }
    }

    /// A test that arrived as homework ("Unit 3 test", due Friday) becomes an exam to count
    /// down to. Returns the exam's ID.
    @discardableResult
    mutating func makeExam(from id: UUID, now: Date = Date()) -> UUID? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let task = tasks.remove(at: index)
        let exam = Exam(title: task.title, subject: task.subject, date: task.due ?? now, hasTime: task.due != nil && task.hasTime,
                        notes: task.notes, source: task.source, emailID: task.emailID)
        exams.append(exam)
        return exam.id
    }

    /// Exams still to come (today's included), soonest first.
    func upcomingExams(now: Date, calendar: Calendar = .current) -> [Exam] {
        exams.filter { !$0.isPast(now: now, calendar: calendar) }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.title < $1.title }
    }

    // MARK: What's due

    /// Not done yet, in the order to do them: overdue and soonest first, then the ones with
    /// no due date, oldest first.
    func open(now: Date = Date()) -> [PlannerTask] {
        tasks.filter { !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x != y ? x < y : a.added < b.added
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.added < b.added
            }
        }
    }

    /// Done, most recently first.
    var finished: [PlannerTask] {
        tasks.filter { $0.done }.sorted { ($0.doneAt ?? $0.added) > ($1.doneAt ?? $1.added) }
    }

    enum Section: Int, CaseIterable {
        case overdue, today, tomorrow, thisWeek, later, someday

        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            case .thisWeek: return "This week"
            case .later: return "Later"
            case .someday: return "No due date"
            }
        }
    }

    static func section(for task: PlannerTask, now: Date, calendar: Calendar = .current) -> Section {
        guard let due = task.due else { return .someday }
        if task.isOverdue(now: now, calendar: calendar) { return .overdue }
        switch DueText.days(until: due, now: now, calendar: calendar) {
        case ...0: return .today
        case 1: return .tomorrow
        case 2...6: return .thisWeek
        default: return .later
        }
    }

    /// What's still to do, grouped by when it's due. Empty groups are left out.
    func sections(now: Date, calendar: Calendar = .current) -> [(section: Section, tasks: [PlannerTask])] {
        let grouped = Dictionary(grouping: open(now: now)) { Planner.section(for: $0, now: now, calendar: calendar) }
        return Section.allCases.compactMap { section in
            guard let tasks = grouped[section], !tasks.isEmpty else { return nil }
            return (section, tasks)
        }
    }

    // MARK: Things found in emails

    static func key(email: String, title: String) -> String {
        email + "|" + Planner.plain(title)
    }

    /// The timetable subject a class name means: "10 Maths A 2026" is "Maths". The longest
    /// subject named in it as whole words wins.
    static func subject(in name: String, among subjects: [String]) -> String? {
        let words = name.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { String($0) }
        guard !words.isEmpty else { return nil }
        var best: String?
        for subject in subjects {
            let wanted = subject.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { String($0) }
            guard !wanted.isEmpty, wanted.count <= words.count else { continue }
            let found = (0...(words.count - wanted.count)).contains { Array(words[$0..<($0 + wanted.count)]) == wanted }
            if found && subject.count > (best?.count ?? 0) {
                best = subject
            }
        }
        return best
    }

    /// A title for matching: lowercase letters and digits only.
    static func plain(_ title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// A task with this title (and, if both say one, the same subject) that isn't from long ago.
    func taskIndex(titled title: String, subject: String) -> Int? {
        let wanted = Planner.plain(title)
        guard !wanted.isEmpty else { return nil }
        let wantedSubject = Planner.plain(subject)
        return tasks.lastIndex { task in
            guard Planner.plain(task.title) == wanted else { return false }
            let subject = Planner.plain(task.subject)
            return wantedSubject.isEmpty || subject.isEmpty || subject == wantedSubject
        }
    }

    /// Adds a task found in an email, unless it's there already (then a missing due date is
    /// filled in) or you removed it before. Returns the task's ID if anything changed.
    @discardableResult
    mutating func take(_ found: PlannerTask, calendar: Calendar = .current) -> UUID? {
        let title = found.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if let email = found.emailID, dismissed.contains(Planner.key(email: email, title: title)) { return nil }
        if let index = taskIndex(titled: title, subject: found.subject) {
            var changed = tasks[index]
            if changed.due == nil, let due = found.due {
                changed.due = due
                changed.hasTime = found.hasTime
            } else if let known = changed.due, !changed.hasTime, found.hasTime, let due = found.due,
                      calendar.isDate(known, inSameDayAs: due) {
                // The same day, now with its time.
                changed.due = due
                changed.hasTime = true
            }
            if changed.subject.isEmpty { changed.subject = found.subject }
            if changed.link == nil { changed.link = found.link }
            if changed.emailID == nil { changed.emailID = found.emailID }
            guard changed != tasks[index] else { return nil }
            tasks[index] = changed
            return changed.id
        }
        var task = found
        task.title = title
        tasks.append(task)
        return task.id
    }

    /// Adds an exam found in an email, unless one with that title on that day is there
    /// already or you removed it before.
    @discardableResult
    mutating func take(_ found: Exam, calendar: Calendar = .current) -> UUID? {
        let title = found.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if let email = found.emailID, dismissed.contains(Planner.key(email: email, title: title)) { return nil }
        let wanted = Planner.plain(title)
        if exams.contains(where: { Planner.plain($0.title) == wanted && calendar.isDate($0.date, inSameDayAs: found.date) }) {
            return nil
        }
        var exam = found
        exam.title = title
        exams.append(exam)
        return exam.id
    }

    /// Marks the task with this title done (a Classroom "returned" email, say).
    @discardableResult
    mutating func finish(titled title: String, subject: String, now: Date = Date()) -> Bool {
        guard let index = taskIndex(titled: title, subject: subject), !tasks[index].done else { return false }
        tasks[index].done = true
        tasks[index].doneAt = now
        return true
    }

    func looked(at email: String) -> Looked? {
        looked[email]
    }

    mutating func markLooked(_ email: String, whole: Bool, byAssistant: Bool, now: Date = Date()) {
        let before = looked[email]
        looked[email] = Looked(at: now, whole: whole || before?.whole == true, byAssistant: byAssistant || before?.byAssistant == true)
    }

    // MARK: Tidying

    /// Clears away tasks finished over a month ago, exams over two weeks past, and the oldest
    /// notes of emails looked through. Returns whether anything went.
    @discardableResult
    mutating func tidy(now: Date = Date()) -> Bool {
        let before = self
        // Cleared-away work that came from an email isn't picked up from it again.
        for task in tasks where task.done && now.timeIntervalSince(task.doneAt ?? task.added) > Planner.keepDoneFor {
            if let email = task.emailID {
                dismissed.insert(Planner.key(email: email, title: task.title))
            }
        }
        tasks.removeAll { $0.done && now.timeIntervalSince($0.doneAt ?? $0.added) > Planner.keepDoneFor }
        exams.removeAll { now.timeIntervalSince($0.date) > Planner.keepExamsFor }
        if looked.count > Planner.keepLooked {
            let newest = looked.sorted { $0.value.at > $1.value.at }.prefix(Planner.keepLooked * 3 / 4)
            looked = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        if dismissed.count > 2000 {
            dismissed = Set(dismissed.sorted().suffix(1500))
        }
        return self != before
    }
}

/// The planner, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Planner.json. It never leaves this Mac unless
/// you let the assistant see it.
final class PlannerStore: ObservableObject {
    @Published private(set) var planner: Planner

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Planner.json")
    }

    init(url: URL = PlannerStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode(Planner.self, from: data) {
            planner = saved
        } else {
            planner = Planner()
        }
    }

    /// Changes the planner and saves it shortly after.
    func change(_ edit: (inout Planner) -> Void) {
        var changed = planner
        edit(&changed)
        guard changed != planner else { return }
        planner = changed
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

    /// Writes the planner to disk straight away (also on quit).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(planner) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save the planner: \(error.localizedDescription)")
        }
    }
}
