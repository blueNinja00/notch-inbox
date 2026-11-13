import Foundation

/// A group of tasks in the agent room that you've made and named: "Biology", "English essay".
struct AgentGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var created: Date

    init(name: String, created: Date = Date()) {
        self.name = name
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, created
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? values.decodeIfPresent(String.self, forKey: .name)) ?? ""
        created = (try? values.decodeIfPresent(Date.self, forKey: .created)) ?? Date(timeIntervalSince1970: 0)
    }

    /// The first group's name. It's always there, and holds whatever is in no other group.
    static let general = "General"

    /// A name as it's given to a new group: on one line, with single spaces, not too long.
    static func clean(_ name: String) -> String {
        let line = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(line.prefix(AgentTeam.longestGroupName)).trimmingCharacters(in: .whitespaces)
    }

    /// What it's called: its name, or "Group" while it has none.
    var title: String {
        let own = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? "Group" : own
    }

    /// How names are matched: whatever their case, accents or spacing.
    static func key(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// How a group's tasks are going: how many are in each state. It's what a group's
/// status bar is drawn from.
struct AgentTally: Equatable {
    var idle = 0
    var queued = 0
    var working = 0
    var done = 0
    var failed = 0
    var stopped = 0
    /// What its tasks have used between them.
    var tokens = 0

    init(_ jobs: [AgentJob] = []) {
        for job in jobs {
            switch job.status {
            case .idle: idle += 1
            case .queued: queued += 1
            case .working: working += 1
            case .done: done += 1
            case .failed: failed += 1
            case .stopped: stopped += 1
            }
            tokens += job.tokens ?? 0
        }
    }

    var total: Int { idle + queued + working + done + failed + stopped }
    /// Going, or about to.
    var active: Int { queued + working }
    var finished: Int { done + failed + stopped }

    /// A stretch of a status bar: one state's share of the group.
    struct Segment: Equatable, Identifiable {
        let status: AgentJob.Status
        let count: Int
        /// Its share of the whole bar, from 0 to 1.
        let share: Double

        var id: String { status.rawValue }
    }

    /// The bar, left to right: what's done, what's working, what's waiting its turn, what
    /// couldn't finish and what was stopped. Tasks not started yet are the empty rest of it.
    var segments: [Segment] {
        guard total > 0 else { return [] }
        let parts: [(AgentJob.Status, Int)] = [(.done, done), (.working, working), (.queued, queued), (.failed, failed), (.stopped, stopped)]
        return parts.filter { $0.1 > 0 }.map { Segment(status: $0.0, count: $0.1, share: Double($0.1) / Double(total)) }
    }

    /// Beside a group's name in the list: "3/5" done of all, or nothing for an empty group.
    var short: String {
        total == 0 ? "" : "\(done)/\(total)"
    }

    /// Under a group's name when it's open: "1 working · 2 ready · 3 done · 41k tokens".
    var line: String {
        guard total > 0 else { return "No tasks yet" }
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if queued > 0 { parts.append("\(queued) waiting") }
        if idle > 0 { parts.append("\(idle) ready") }
        if done > 0 { parts.append("\(done) done") }
        if failed > 0 { parts.append(failed == 1 ? "1 couldn't finish" : "\(failed) couldn't finish") }
        if stopped > 0 { parts.append("\(stopped) stopped") }
        if tokens > 0 { parts.append("\(UsageText.tokens(tokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    /// For a group's tooltip and VoiceOver: "Biology: 1 working, 2 ready, 3 done".
    func spoken(for name: String) -> String {
        guard total > 0 else { return "\(name): no tasks yet" }
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if queued > 0 { parts.append("\(queued) waiting") }
        if idle > 0 { parts.append("\(idle) ready") }
        if done > 0 { parts.append("\(done) done") }
        if failed > 0 { parts.append("\(failed) couldn't finish") }
        if stopped > 0 { parts.append("\(stopped) stopped") }
        return "\(name): " + parts.joined(separator: ", ")
    }
}

extension AgentTeam {
    /// A group you made, by its id. nil for the first group, or one that's gone.
    func group(_ id: UUID?) -> AgentGroup? {
        guard let id = id else { return nil }
        return groups.first { $0.id == id }
    }

    /// What a group is called: "General" for the first one (and for one that's gone).
    func groupName(_ id: UUID?) -> String {
        group(id)?.title ?? AgentGroup.general
    }

    /// The group with this name, whatever its case or spacing. ("General" is the first
    /// group, which has no id, so it isn't found here.)
    func group(named name: String) -> AgentGroup? {
        let wanted = AgentGroup.key(name)
        guard !wanted.isEmpty else { return nil }
        return groups.first { AgentGroup.key($0.name) == wanted }
    }

    /// Every group as the room lists them: the first group (nil), then yours in order.
    var groupIDs: [UUID?] {
        [nil] + groups.map { Optional($0.id) }
    }

    /// The tasks in a group, newest first. The first group (nil) has everything that's in
    /// none of yours, including tasks whose group has been taken away.
    func jobs(in group: UUID?) -> [AgentJob] {
        let own = self.group(group)?.id
        return newestFirst.filter { job in
            let theirs = self.group(job.group)?.id
            return theirs == own
        }
    }

    func tally(in group: UUID?) -> AgentTally {
        AgentTally(jobs(in: group))
    }

    /// How many finished tasks "Clear Done" would take out of a group.
    func clearable(in group: UUID?) -> Int {
        let held = heldForChains
        return jobs(in: group).filter { $0.isFinished && !held.contains($0.id) }.count
    }

    /// The group after (or before) this one in the list, going round at the ends.
    func group(after group: UUID?, by offset: Int) -> UUID? {
        let all = groupIDs
        let own = self.group(group)?.id
        guard let index = all.firstIndex(of: own), all.count > 1 else { return own }
        let next = ((index + offset) % all.count + all.count) % all.count
        return all[next]
    }

    /// The task after (or before) this one in its group's table, stopping at the ends.
    /// With none picked, the first (or the last).
    func job(after id: UUID?, in group: UUID?, by offset: Int) -> UUID? {
        let listed = jobs(in: group)
        guard !listed.isEmpty else { return nil }
        guard let index = listed.firstIndex(where: { $0.id == id }) else {
            return offset >= 0 ? listed.first?.id : listed.last?.id
        }
        return listed[min(max(index + offset, 0), listed.count - 1)].id
    }

    /// The groups in words, for the assistant: their names and how each is going.
    var groupsLine: String {
        guard !groups.isEmpty else { return "" }
        let named = groupIDs.map { id -> String in
            let tally = self.tally(in: id)
            return tally.total == 0 ? groupName(id) : "\(groupName(id)) (\(tally.total))"
        }
        return "The user's task groups: " + named.joined(separator: ", ") + "."
    }
}

extension AgentJob {
    /// How it's going, in a word or two, for the table: "Ready", "Searching the web for
    /// tides", "Done". (A task held back by the day's usage cap says so.)
    var statusLabel: String {
        switch status {
        case .idle: return "Ready"
        case .queued: return activity.isEmpty ? "Waiting its turn" : activity
        case .working: return activity.isEmpty ? "Working" : activity
        case .done: return "Done"
        case .failed: return "Couldn't finish"
        case .stopped: return "Stopped"
        }
    }

    /// What goes after that, more quietly: a finished task's first words, or why one
    /// didn't finish.
    var statusNote: String {
        switch status {
        case .done:
            return AgentReport.firstLine(report, limit: 90)
        case .failed, .stopped:
            return AgentStream.shorten(problem ?? "", to: 90)
        default:
            return ""
        }
    }
}
