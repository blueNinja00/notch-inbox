import Foundation
#if canImport(Combine)
import Combine
#endif

/// What one run of the assistant or an agent read and wrote, counted in tokens (the pieces
/// of words a model works in: a token is about three-quarters of a word).
struct TokenUse: Equatable, Codable {
    /// Read for the first time.
    var input = 0
    /// Written.
    var output = 0
    /// Read and kept ready for the next step.
    var cacheWrite = 0
    /// Read again from what was kept ready. An agent re-reads its whole job at every step,
    /// so this is the biggest number, and the cheapest.
    var cacheRead = 0
    /// Claude Code's own estimate of what the run would cost at API prices, in US dollars.
    /// On a Claude plan nothing is charged; it's a yardstick for how much of the plan a run used.
    var cost: Double?

    /// The meter's one number. Re-reading counts at a tenth, as it does for cost.
    var tokens: Int { input + output + cacheWrite + cacheRead / 10 }

    var isEmpty: Bool { input == 0 && output == 0 && cacheWrite == 0 && cacheRead == 0 && (cost ?? 0) == 0 }

    static func int(_ value: Any?) -> Int {
        if let number = value as? Int { return max(0, number) }
        if let number = value as? Double, number.isFinite { return max(0, Int(number)) }
        return 0
    }

    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// From the last line Claude Code prints for a run (its "result"): the whole run's
    /// tokens and estimated cost. Nil for any other line.
    static func fromResult(line: String) -> TokenUse? {
        guard line.contains("\"result\""), let fields = object(line), fields["type"] as? String == "result" else { return nil }
        return fromResult(fields)
    }

    static func fromResult(_ fields: [String: Any]) -> TokenUse? {
        var use = TokenUse()
        // By model when it's there: that count includes any helpers the run started.
        if let models = fields["modelUsage"] as? [String: Any], !models.isEmpty {
            var cost = 0.0
            for entry in models.values {
                guard let model = entry as? [String: Any] else { continue }
                use.input += int(model["inputTokens"])
                use.output += int(model["outputTokens"])
                use.cacheWrite += int(model["cacheCreationInputTokens"])
                use.cacheRead += int(model["cacheReadInputTokens"])
                cost += (model["costUSD"] as? Double) ?? 0
            }
            if cost > 0 { use.cost = cost }
        } else if let usage = fields["usage"] as? [String: Any] {
            use.take(usage)
        }
        if let cost = fields["total_cost_usd"] as? Double, cost.isFinite, cost > 0 {
            use.cost = cost
        }
        return use.isEmpty ? nil : use
    }

    /// Fills in from a "usage" object as the API writes it.
    mutating func take(_ usage: [String: Any]) {
        input = TokenUse.int(usage["input_tokens"])
        output = max(output, TokenUse.int(usage["output_tokens"]))
        cacheWrite = TokenUse.int(usage["cache_creation_input_tokens"])
        cacheRead = TokenUse.int(usage["cache_read_input_tokens"])
    }

    /// From an answer that came straight from the API in one piece.
    static func fromAPI(body: Data) -> TokenUse? {
        guard let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let usage = fields["usage"] as? [String: Any] else { return nil }
        var use = TokenUse()
        use.take(usage)
        return use.isEmpty ? nil : use
    }

    /// Follows an answer streaming from the API: its events say what was read as it
    /// starts, and what was written as it goes.
    mutating func takeAPI(line: String) {
        guard line.hasPrefix("data:"), line.contains("\"usage\""),
              let fields = TokenUse.object(String(line.dropFirst(5))) else { return }
        if fields["type"] as? String == "message_start", let message = fields["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            take(usage)
        } else if fields["type"] as? String == "message_delta", let usage = fields["usage"] as? [String: Any] {
            output = max(output, TokenUse.int(usage["output_tokens"]))
        }
    }

    static func + (one: TokenUse, other: TokenUse) -> TokenUse {
        var sum = TokenUse(input: one.input + other.input, output: one.output + other.output,
                           cacheWrite: one.cacheWrite + other.cacheWrite, cacheRead: one.cacheRead + other.cacheRead)
        if one.cost != nil || other.cost != nil {
            sum.cost = (one.cost ?? 0) + (other.cost ?? 0)
        }
        return sum
    }
}

/// Counts what an agent has used so far, from the lines Claude Code prints as it works.
/// Each step's reading is counted once as it happens; the run's last line then gives the
/// full count, writing and cost included, which takes its place.
struct TokenTally: Equatable {
    private(set) var use = TokenUse()
    /// Whether the run's own final count has arrived.
    private(set) var final = false
    private var seen: Set<String> = []

    /// Takes a line. True if the count changed.
    @discardableResult
    mutating func take(line: String) -> Bool {
        guard !final, line.contains("\"usage\"") || line.contains("\"modelUsage\""),
              let data = line.data(using: .utf8),
              let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        switch fields["type"] as? String {
        case "result":
            guard let whole = TokenUse.fromResult(fields) else { return false }
            use = whole
            final = true
            return true
        case "assistant":
            // A helper's messages aren't this agent's own steps; and one step can arrive
            // as several messages with the same ID.
            guard !(fields["parent_tool_use_id"] is String), let message = fields["message"] as? [String: Any],
                  let id = message["id"] as? String, !seen.contains(id), let usage = message["usage"] as? [String: Any] else { return false }
            seen.insert(id)
            use.input += TokenUse.int(usage["input_tokens"])
            use.cacheWrite += TokenUse.int(usage["cache_creation_input_tokens"])
            use.cacheRead += TokenUse.int(usage["cache_read_input_tokens"])
            return true
        default:
            return false
        }
    }
}

/// What the tokens were used for.
enum UsageKind: String, Codable, CaseIterable {
    /// Questions you asked the assistant.
    case chat
    /// Agents' jobs.
    case agent
    /// The chief of staff's answers in the team chat.
    case team
    /// Planning an assignment's steps, reading a task sheet, finding due dates in mail.
    case other

    var title: String {
        switch self {
        case .chat: return "Questions"
        case .agent: return "Agents"
        case .team: return "Team chat"
        case .other: return "Planning and reading"
        }
    }
}

/// The notch's own count of the Claude it has used: by day and by what for, with the
/// latest runs. It counts only what the notch did, not your other use of Claude.
struct UsageLog: Equatable, Codable {
    struct Totals: Equatable, Codable {
        var tokens = 0
        var cost = 0.0
        var runs = 0

        mutating func add(_ other: Totals) {
            tokens += other.tokens
            cost += other.cost
            runs += other.runs
        }
    }

    struct Entry: Identifiable, Equatable, Codable {
        var id = UUID()
        var at: Date
        var kind: UsageKind
        /// The agent's name, or what the run was for.
        var label: String
        var tokens: Int
        var cost: Double?
        var model: String
    }

    /// Day ("2026-11-12") → what for → how much.
    private(set) var days: [String: [String: Totals]] = [:]
    private(set) var recent: [Entry] = []

    static let keepDays = 120
    static let keepRecent = 60

    init() {}

    private enum CodingKeys: String, CodingKey {
        case days, recent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? values.decodeIfPresent([String: [String: Totals]].self, forKey: .days)) ?? [:]
        recent = (try? values.decodeIfPresent([Entry].self, forKey: .recent)) ?? []
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return "\(parts.year ?? 2000)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
    }

    /// Adds one run to the count.
    mutating func record(_ use: TokenUse, kind: UsageKind, label: String = "", model: String = "", now: Date = Date(), calendar: Calendar = .current) {
        guard !use.isEmpty else { return }
        let key = UsageLog.key(for: now, calendar: calendar)
        var day = days[key] ?? [:]
        var totals = day[kind.rawValue] ?? Totals()
        totals.add(Totals(tokens: use.tokens, cost: use.cost ?? 0, runs: 1))
        day[kind.rawValue] = totals
        days[key] = day
        recent.append(Entry(at: now, kind: kind, label: String(label.prefix(60)), tokens: use.tokens, cost: use.cost, model: model))
        if recent.count > UsageLog.keepRecent {
            recent.removeFirst(recent.count - UsageLog.keepRecent)
        }
        if days.count > UsageLog.keepDays {
            for old in days.keys.sorted().prefix(days.count - UsageLog.keepDays) {
                days[old] = nil
            }
        }
    }

    /// The days that count: today and the `count - 1` before it.
    private func keys(days count: Int, now: Date, calendar: Calendar) -> [String] {
        (0..<max(1, count)).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map { UsageLog.key(for: $0, calendar: calendar) }
        }
    }

    /// Everything over the last `count` days (1 is today).
    func total(days count: Int, now: Date = Date(), calendar: Calendar = .current) -> Totals {
        var sum = Totals()
        for key in keys(days: count, now: now, calendar: calendar) {
            for totals in (days[key] ?? [:]).values {
                sum.add(totals)
            }
        }
        return sum
    }

    /// The same, split by what it was for; kinds with nothing are left out.
    func byKind(days count: Int, now: Date = Date(), calendar: Calendar = .current) -> [(kind: UsageKind, totals: Totals)] {
        var sums: [UsageKind: Totals] = [:]
        for key in keys(days: count, now: now, calendar: calendar) {
            for (name, totals) in days[key] ?? [:] {
                guard let kind = UsageKind(rawValue: name) else { continue }
                var sum = sums[kind] ?? Totals()
                sum.add(totals)
                sums[kind] = sum
            }
        }
        return UsageKind.allCases.compactMap { kind in sums[kind].map { (kind, $0) } }
    }

    func today(now: Date = Date(), calendar: Calendar = .current) -> Totals {
        total(days: 1, now: now, calendar: calendar)
    }

    /// Whether today's count has reached the cap you set (0 is no cap).
    func isOver(cap: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        cap > 0 && today(now: now, calendar: calendar).tokens >= cap
    }

    mutating func clear() {
        days = [:]
        recent = []
    }
}

/// Usage in words.
enum UsageText {
    /// The caps on offer, in tokens a day; 0 is none.
    static let caps = [0, 1_000_000, 2_000_000, 5_000_000, 10_000_000]

    /// "840", "12k", "412k", "1.2M".
    static func tokens(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 10_000 {
            let tenths = (Double(count) / 100).rounded() / 10
            return tenths == tenths.rounded() ? "\(Int(tenths))k" : "\(tenths)k"
        }
        if count < 1_000_000 { return "\(Int((Double(count) / 1000).rounded()))k" }
        let tenths = (Double(count) / 100_000).rounded() / 10
        return tenths == tenths.rounded() ? "\(Int(tenths))M" : "\(tenths)M"
    }

    /// "$0.04", "$1.20", "under 1¢".
    static func cost(_ dollars: Double) -> String {
        if dollars < 0.005 { return "under 1¢" }
        let cents = Int((dollars * 100).rounded())
        let rest = cents % 100
        return "$\(cents / 100).\(rest < 10 ? "0" : "")\(rest)"
    }

    static func cap(_ tokens: Int) -> String {
        tokens == 0 ? "Off" : UsageText.tokens(tokens)
    }

    /// "1.2M tokens · about $0.45 at API prices · 14 runs", or "Nothing yet".
    static func line(_ totals: UsageLog.Totals) -> String {
        guard totals.runs > 0 else { return "Nothing yet" }
        var parts = ["\(tokens(totals.tokens)) tokens"]
        if totals.cost > 0 {
            parts.append("about \(cost(totals.cost)) at API prices")
        }
        parts.append(totals.runs == 1 ? "1 run" : "\(totals.runs) runs")
        return parts.joined(separator: " · ")
    }

    /// "412k tokens", with the cost when it's known: for one agent's floor.
    static func run(tokens count: Int, cost dollars: Double?) -> String {
        guard count > 0 else { return "" }
        if let dollars = dollars, dollars > 0 {
            return "\(tokens(count)) tokens (\(cost(dollars)))"
        }
        return "\(tokens(count)) tokens"
    }

    /// "Questions 310k · Agents 2.1M": where it went.
    static func breakdown(_ kinds: [(kind: UsageKind, totals: UsageLog.Totals)]) -> String {
        kinds.filter { $0.totals.tokens > 0 }.map { "\($0.kind.title) \(tokens($0.totals.tokens))" }.joined(separator: " · ")
    }

    /// The tag in the agent room: "Today 1.2M", or "Today 2.1M of 2M" with a cap.
    static func todayTag(_ totals: UsageLog.Totals, cap: Int) -> String {
        cap > 0 ? "Today \(tokens(totals.tokens)) of \(tokens(cap))" : "Today \(tokens(totals.tokens))"
    }

    static let held = "Held: today's usage cap is reached"
}

/// The count, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Usage.json.
final class UsageStore: ObservableObject {
    @Published private(set) var log: UsageLog

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Usage.json")
    }

    init(url: URL = UsageStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? UsageStore.decoder.decode(UsageLog.self, from: data) {
            log = saved
        } else {
            log = UsageLog()
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// Adds a run to the count (on the main thread).
    func record(_ use: TokenUse?, kind: UsageKind, label: String = "", model: String = "") {
        guard let use = use, !use.isEmpty else { return }
        var changed = log
        changed.record(use, kind: kind, label: label, model: model)
        log = changed
        saveSoon()
    }

    func clear() {
        log = UsageLog()
        saveNow()
    }

    private func saveSoon() {
        guard pendingSave == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(log) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save the usage count: \(error.localizedDescription)")
        }
    }
}
