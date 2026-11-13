import Foundation
#if canImport(Combine)
import Combine
#endif

/// One agent's report as the library keeps it. A chain's entry has one of these for each
/// of its stages: the researcher's notes, the draft, the checked version.
struct ReportPart: Identifiable, Equatable, Codable {
    /// The agent that wrote it.
    var id: UUID
    /// Its part in a chain ("Researcher"), or "" for an agent working alone.
    var role: String
    /// Where it came in its chain, from 0.
    var stage: Int
    var text: String
    /// Its folder, and the files it saved there.
    var folder: String
    var files: [String]
    var finished: Date

    private enum CodingKeys: String, CodingKey {
        case id, role, stage, text, folder, files, finished
    }

    init(id: UUID, role: String, stage: Int, text: String, folder: String, files: [String], finished: Date) {
        self.id = id
        self.role = role
        self.stage = stage
        self.text = text
        self.folder = folder
        self.files = files
        self.finished = finished
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        role = (try? values.decodeIfPresent(String.self, forKey: .role)) ?? ""
        stage = (try? values.decodeIfPresent(Int.self, forKey: .stage)) ?? 0
        text = (try? values.decodeIfPresent(String.self, forKey: .text)) ?? ""
        folder = (try? values.decodeIfPresent(String.self, forKey: .folder)) ?? ""
        files = (try? values.decodeIfPresent([String].self, forKey: .files)) ?? []
        finished = (try? values.decodeIfPresent(Date.self, forKey: .finished)) ?? Date(timeIntervalSince1970: 0)
    }

    /// What its tab is called in the library: what that stage of a chain hands over.
    var label: String {
        switch role {
        case "Researcher": return "Research notes"
        case "Writer": return "Draft"
        case "Planner": return "Plan"
        case "Checker": return "Checked"
        default: return role.isEmpty ? "Report" : role
        }
    }
}

/// A finished piece of work in the library: what was asked, and what came back.
struct LibraryReport: Identifiable, Equatable, Codable {
    /// The agent that did it; for a chain, the first of its agents.
    var id: UUID
    var title: String
    /// What was asked for (its start, if it was long).
    var task: String
    /// When its newest part was finished.
    var made: Date
    /// Whether the assistant handed the job out (or you did, in the room).
    var fromAssistant: Bool
    /// One part for an agent working alone; a chain's stages in order.
    var parts: [ReportPart]
    /// The first words of its last part, for the list.
    var preview: String
    /// The subject it's pinned to ("" for none), and the assignment.
    var subject: String
    var assignment: UUID?

    private enum CodingKeys: String, CodingKey {
        case id, title, task, made, fromAssistant, parts, preview, subject, assignment
    }

    init(id: UUID, title: String, task: String, made: Date, fromAssistant: Bool, parts: [ReportPart], subject: String = "", assignment: UUID? = nil) {
        self.id = id
        self.title = title
        self.task = task
        self.made = made
        self.fromAssistant = fromAssistant
        self.parts = parts
        self.preview = LibraryReport.preview(of: parts)
        self.subject = subject
        self.assignment = assignment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
        task = (try? values.decodeIfPresent(String.self, forKey: .task)) ?? ""
        made = (try? values.decodeIfPresent(Date.self, forKey: .made)) ?? Date(timeIntervalSince1970: 0)
        fromAssistant = (try? values.decodeIfPresent(Bool.self, forKey: .fromAssistant)) ?? false
        parts = (try? values.decodeIfPresent([ReportPart].self, forKey: .parts)) ?? []
        preview = (try? values.decodeIfPresent(String.self, forKey: .preview)) ?? LibraryReport.preview(of: parts)
        subject = (try? values.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        assignment = try? values.decodeIfPresent(UUID.self, forKey: .assignment)
    }

    /// The first line of words of the last part there is.
    static func preview(of parts: [ReportPart]) -> String {
        AgentReport.firstLine(parts.last?.text ?? "", limit: 120)
    }

    /// The part that's shown first: the last stage there is.
    var newest: ReportPart? { parts.last }

    func part(_ id: UUID?) -> ReportPart? {
        guard let id = id else { return newest }
        return parts.first { $0.id == id } ?? newest
    }

    var isChain: Bool { parts.count > 1 || !(parts.first?.role ?? "").isEmpty }

    var isPinned: Bool { !subject.isEmpty || assignment != nil }

    /// "Reef report" for its name; "Report" if it somehow has none.
    var name: String {
        let own = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? "Report" : own
    }

    /// Under its name when it's open: "A chain of 3 · from the assistant".
    var about: String {
        var words: [String] = []
        if isChain {
            words.append(parts.count == 1 ? "A chain, 1 stage kept" : "A chain, \(parts.count) stages kept")
        }
        words.append(fromAssistant ? "Handed out by the assistant" : "Handed out by you")
        return words.joined(separator: " · ")
    }
}

/// Every report your agents have finished, kept so that it can be found again after its
/// agent has left the room. Searchable, and each can be pinned to a subject or an assignment.
struct ReportLibrary: Equatable, Codable {
    private(set) var reports: [LibraryReport] = []

    /// How many are kept, and how much of each.
    static let keep = 120
    static let longestText = AgentTeam.mostReport
    static let longestTask = 600
    static let longestTitle = 80
    static let longestSubject = 60

    private enum CodingKeys: String, CodingKey {
        case reports
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reports = (try? values.decodeIfPresent([LibraryReport].self, forKey: .reports)) ?? []
    }

    func report(_ id: UUID?) -> LibraryReport? {
        guard let id = id else { return nil }
        return reports.first { $0.id == id }
    }

    /// The entry that holds this agent's report, as any of its parts.
    func entry(holding agent: UUID?) -> LibraryReport? {
        guard let agent = agent else { return nil }
        return reports.first { $0.id == agent || $0.parts.contains { $0.id == agent } }
    }

    var newestFirst: [LibraryReport] {
        reports.sorted { $0.made != $1.made ? $0.made > $1.made : $0.name < $1.name }
    }

    /// The subjects that reports are pinned to, the one used most recently first.
    var subjects: [String] {
        var seen: [String] = []
        for report in newestFirst where !report.subject.isEmpty {
            if !seen.contains(where: { ReportLibrary.same($0, report.subject) }) {
                seen.append(report.subject)
            }
        }
        return seen
    }

    static func same(_ one: String, _ other: String) -> Bool {
        fold(one) == fold(other)
    }

    /// Lower case, without accents, with single spaces: how names are matched.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The subjects a report can be pinned to: your timetable's classes, then any others
    /// your assignments or the library already use. Each once, as it was first written.
    static func pinSubjects(classes: [String], assignments: [String], own: [String]) -> [String] {
        var seen: [String] = []
        for name in classes + assignments + own {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, !seen.contains(where: { same($0, clean) }) {
                seen.append(clean)
            }
        }
        return seen
    }

    // MARK: Filing

    /// Files a finished agent's report. An agent working alone gets an entry of its own; a
    /// stage of a chain joins its chain's entry, and one that's done again replaces what it
    /// wrote before. `subject` is the subject of the assignment it was for, if any.
    /// Nothing is filed for an agent that didn't finish, or left no report.
    @discardableResult
    mutating func file(_ job: AgentJob, subject: String = "", now: Date = Date()) -> LibraryReport? {
        let text = job.report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard job.status == .done, !text.isEmpty else { return nil }
        let part = ReportPart(id: job.id, role: job.chain?.role ?? "", stage: job.chain?.stage ?? 0, text: String(text.prefix(ReportLibrary.longestText)),
                              folder: job.folder, files: job.files, finished: job.finished ?? now)
        let root = job.chain?.earlier.first ?? job.id
        if let index = reports.firstIndex(where: { $0.id == root }) {
            reports[index].parts.removeAll { $0.id == part.id || $0.stage == part.stage }
            reports[index].parts.append(part)
            reports[index].parts.sort { $0.stage < $1.stage }
            reports[index].made = max(reports[index].made, part.finished)
            reports[index].preview = LibraryReport.preview(of: reports[index].parts)
            return reports[index]
        }
        var title = (job.chain?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = job.name
        }
        let entry = LibraryReport(id: root, title: title, task: ReportLibrary.start(of: job.task), made: part.finished,
                                  fromAssistant: job.origin == .chief, parts: [part],
                                  subject: String(subject.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ReportLibrary.longestSubject)),
                                  assignment: job.chain?.source)
        reports.append(entry)
        trim()
        return entry
    }

    /// The start of a job, as the library keeps it.
    static func start(of task: String) -> String {
        let whole = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whole.count > longestTask else { return whole }
        return String(whole.prefix(longestTask)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// The first time the library is opened: the reports of the agents still in the room go in.
    mutating func fill(from team: AgentTeam, subject: (UUID) -> String = { _ in "" }) {
        for job in team.jobs {
            file(job, subject: job.chain?.source.map(subject) ?? "")
        }
    }

    /// Lets the oldest go once there are too many: ones that aren't pinned first.
    private mutating func trim() {
        guard reports.count > ReportLibrary.keep else { return }
        var over = reports.count - ReportLibrary.keep
        let oldestFirst = Array(newestFirst.reversed())
        for report in oldestFirst where over > 0 && !report.isPinned {
            reports.removeAll { $0.id == report.id }
            over -= 1
        }
        for report in oldestFirst where over > 0 && report.isPinned {
            reports.removeAll { $0.id == report.id }
            over -= 1
        }
    }

    // MARK: Changing

    /// A new name, as it's typed.
    mutating func rename(_ id: UUID, to title: String) {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[index].title = String(title.filter { !$0.isNewline }.prefix(ReportLibrary.longestTitle))
    }

    /// Pins it to a subject ("" unpins it from its subject).
    mutating func pin(_ id: UUID, subject: String) {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[index].subject = String(subject.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ReportLibrary.longestSubject))
    }

    /// Pins it to an assignment (nil unpins it). With `subject`, it takes the assignment's
    /// subject too, if it had none of its own.
    mutating func pin(_ id: UUID, assignment: UUID?, subject: String = "") {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[index].assignment = assignment
        if assignment != nil, reports[index].subject.isEmpty {
            reports[index].subject = String(subject.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ReportLibrary.longestSubject))
        }
    }

    mutating func remove(_ id: UUID) {
        reports.removeAll { $0.id == id }
    }

    /// Reports pinned to an assignment that's been deleted stay, pinned to nothing.
    mutating func keepPins(to assignments: Set<UUID>) {
        for index in reports.indices {
            if let pinned = reports[index].assignment, !assignments.contains(pinned) {
                reports[index].assignment = nil
            }
        }
    }

    // MARK: Finding

    /// The reports pinned to an assignment, newest first.
    func pinned(to assignment: UUID) -> [LibraryReport] {
        newestFirst.filter { $0.assignment == assignment }
    }

    /// Whether a word is somewhere in some text, whatever its case or accents.
    static func has(_ word: String, in text: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The reports that have every word of what was typed, in their name, what was asked
    /// or what came back, with any one subject picked. Those with the words in their name
    /// come first; otherwise the newest do.
    func search(_ query: String, subject: String = "") -> [LibraryReport] {
        let words = ReportLibrary.fold(query).split(separator: " ").map(String.init)
        var found = newestFirst
        if !subject.isEmpty {
            found = found.filter { ReportLibrary.same($0.subject, subject) }
        }
        guard !words.isEmpty else { return found }
        var inName: [LibraryReport] = []
        var elsewhere: [LibraryReport] = []
        for report in found {
            let name = report.title + " " + report.subject
            if words.allSatisfy({ ReportLibrary.has($0, in: name) }) {
                inName.append(report)
            } else if words.allSatisfy({ word in
                ReportLibrary.has(word, in: name) || ReportLibrary.has(word, in: report.task) || report.parts.contains { ReportLibrary.has(word, in: $0.text) }
            }) {
                elsewhere.append(report)
            }
        }
        return inName + elsewhere
    }

    /// For a search's results: the words around the first place the search turns up in the
    /// report (its first word that's in the report itself, in the newest part that has it).
    /// Without a search, or if it only matched the name, the report's first line.
    static func snippet(of report: LibraryReport, for query: String, around: Int = 60) -> String {
        for word in fold(query).split(separator: " ").map(String.init) {
            for part in report.parts.reversed() {
                let text = part.text
                guard let found = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let start = text.index(found.lowerBound, offsetBy: -around, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(found.upperBound, offsetBy: around, limitedBy: text.endIndex) ?? text.endIndex
                // (Without the marks its formatting is written in.)
                let words = AgentReport.plain(String(text[start..<end]))
                    .split(whereSeparator: { $0.isWhitespace || $0 == "#" || $0 == "|" || $0 == "*" })
                    .joined(separator: " ")
                guard !words.isEmpty else { continue }
                return (start > text.startIndex ? "…" : "") + words + (end < text.endIndex ? "…" : "")
            }
        }
        return report.preview
    }

    /// The part of a report to open from a search: the newest one that has what was typed.
    /// (nil without a search, or if only its name matched: it opens at its last part.)
    static func part(of report: LibraryReport, matching query: String) -> UUID? {
        for word in fold(query).split(separator: " ").map(String.init) {
            if let part = report.parts.last(where: { has(word, in: $0.text) }) {
                return part.id
            }
        }
        return nil
    }

    /// "12 reports", for the room and Copy Debug Info.
    var countLine: String {
        reports.count == 1 ? "1 report" : "\(reports.count) reports"
    }

    /// Beside the library's name: how many there are, or how many of them are showing.
    func countLine(showing: Int, narrowed: Bool) -> String {
        narrowed ? "\(showing) of \(reports.count)" : countLine
    }

    /// What the list says when there's nothing to show.
    static func emptyLine(any: Bool, searching: Bool, subject: String) -> String {
        guard any else {
            return "Nothing here yet. When an agent finishes, its report is kept here, so you can find it again after the agent has left the room."
        }
        if searching {
            return subject.isEmpty ? "No report has those words." : "No report pinned to \(subject) has those words."
        }
        return subject.isEmpty ? "Nothing to show." : "Nothing is pinned to \(subject)."
    }

    /// Whether a folder kept with a report really is one of the agents' own: inside the
    /// folder all of theirs go in. (Only those are opened from the library.)
    static func isAgentsFolder(_ folder: String, home: String = AgentBrief.home.path) -> Bool {
        guard folder.hasPrefix("/"), !home.isEmpty else { return false }
        let base = (home as NSString).standardizingPath
        let whole = (folder as NSString).standardizingPath
        return whole.hasPrefix(base + "/")
    }
}

/// The library, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Reports.json.
final class ReportsStore: ObservableObject {
    @Published private(set) var library: ReportLibrary
    /// There was no library yet when the app started: it's filled from the agent room.
    let isNew: Bool

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Reports.json")
    }

    init(url: URL = ReportsStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode(ReportLibrary.self, from: data) {
            library = saved
            isNew = false
        } else {
            library = ReportLibrary()
            isNew = !FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Changes the library and saves it shortly after.
    func change(_ edit: (inout ReportLibrary) -> Void) {
        var changed = library
        edit(&changed)
        guard changed != library else { return }
        library = changed
        saveSoon()
    }

    private func saveSoon() {
        guard pendingSave == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Writes the library to disk straight away (also on quit).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(library) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save the report library: \(error.localizedDescription)")
        }
    }
}
