import Foundation

/// Runs your agents. With Claude through Claude Code, each agent is its own `claude` run,
/// working over many turns in a folder of its own: it can search the web and read pages
/// (if that's switched on), read and write files in its folder, and read folders you've
/// chosen. It has no shell and nothing else on the Mac. With the other engines an agent
/// can only think and write. Only a few work at once; the rest wait their turn.
final class AgentRunner {
    private let store: AgentsStore
    private let assistant: Assistant
    private let settings: AppSettings
    private var running: [UUID: Task<Void, Never>] = [:]

    /// An agent finished, one way or another (for the chime).
    var onFinished: ((AgentJob) -> Void)?
    /// The team chat's desk, when agents share one.
    var desk: TeamDesk?

    /// The longest an agent may work.
    static let timeLimit: TimeInterval = 25 * 60

    init(store: AgentsStore, assistant: Assistant, settings: AppSettings) {
        self.store = store
        self.assistant = assistant
        self.settings = settings
    }

    /// Hands out a job. It starts as soon as there's a free place.
    @discardableResult
    func start(name: String, task: String, origin: AgentJob.Origin, chat: UUID? = nil) -> AgentJob? {
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var added: AgentJob?
        store.change { added = $0.add(name: name, task: task, origin: origin, chat: chat) }
        pump()
        return added
    }

    /// Hands a job to a chain: a researcher starts on it, and each of the others takes
    /// over as the one before finishes. `source` is the assignment it's for, if any.
    @discardableResult
    func startChain(title: String, goal: String, kind: AgentChain.Kind, origin: AgentJob.Origin, source: UUID? = nil,
                    chat: UUID? = nil) -> AgentJob? {
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var added: AgentJob?
        store.change { added = $0.addChain(title: title, goal: goal, kind: kind, origin: origin, source: source, chat: chat) }
        pump()
        return added
    }

    func stop(_ id: UUID) {
        running[id]?.cancel()
        running[id] = nil
        store.change { $0.stop(id) }
        pump()
    }

    /// The same job again, as a new agent.
    @discardableResult
    func again(_ id: UUID) -> AgentJob? {
        var added: AgentJob?
        store.change { added = $0.again(id) }
        pump()
        return added
    }

    /// A stage of a chain stopped short: the next agent starts from what it left.
    @discardableResult
    func carryOn(_ id: UUID) -> AgentJob? {
        var added: AgentJob?
        store.change { added = $0.carryOn(id) }
        pump()
        return added
    }

    func remove(_ id: UUID) {
        store.change { $0.remove(id) }
    }

    func clearFinished() {
        store.change { $0.clearFinished() }
    }

    /// Stops everything (the app is quitting). What each agent had written so far is kept.
    func stopAll() {
        for task in running.values {
            task.cancel()
        }
        running = [:]
        store.change { $0.interrupt() }
        store.saveNow()
    }

    /// Starts waiting jobs while there's room for them, unless the day's usage cap has
    /// been reached: then they're held, and looked at again every ten minutes.
    func pump() {
        if assistant.usage.log.isOver(cap: settings.agentDailyCap) {
            guard !store.team.queued.isEmpty else { return }
            store.change { $0.hold(UsageText.held) }
            lookAgainLater()
            return
        }
        store.change { $0.unhold() }
        for job in store.team.ready(limit: settings.agentsAtOnce) where running[job.id] == nil {
            begin(job)
        }
    }

    private var lookingAgain = false

    private func lookAgainLater() {
        guard !lookingAgain else { return }
        lookingAgain = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
            self?.lookingAgain = false
            self?.pump()
        }
    }

    private func begin(_ job: AgentJob) {
        let id = job.id
        let engine = assistant.engine
        let model = assistant.claudeModel
        let tools = engine == .claudeCode
        let folder = AgentBrief.home.appendingPathComponent(AgentBrief.folderName(for: job.name, id: id), isDirectory: true)
        if tools {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        store.change { $0.begin(id, folder: tools ? folder.path : "", model: assistant.modelName) }

        let web = tools && settings.agentsUseWeb
        var readFolders = tools ? settings.agentReadFolders.filter { AgentRunner.isFolder($0) } : []
        // The team chat: a file every agent may read (and none may change).
        var teamChat: String?
        if tools, settings.agentsTeamChat, let desk = desk, desk.writeChat() {
            readFolders.append(TeamChat.room.path)
            teamChat = TeamChat.file.path
        }
        // In a chain, it may read (and not change) what the stages before it saved.
        if tools, let chain = job.chain {
            for earlier in chain.earlierFolders(in: store.team) where AgentRunner.isFolder(earlier) && !readFolders.contains(earlier) {
                readFolders.append(earlier)
            }
        }
        let system = AgentBrief.system(now: Date(), tools: tools, web: web, readFolders: readFolders, teamChat: teamChat)
        let prompt = AgentBrief.prompt(for: job, team: store.team, tools: tools, web: web)
        let path = assistant.claudePath

        let work = Task { [weak self] in
            guard let self = self else { return }
            if tools {
                await self.runWithClaudeCode(id: id, path: path, model: model, system: system, web: web, readFolders: readFolders,
                                             prompt: prompt, folder: folder)
            } else {
                await self.runWithoutTools(id: id, system: system, prompt: prompt, model: model)
            }
            // What it saved, as its folder really has it (not just what it said it wrote).
            let saved = tools ? AgentFiles.list(in: folder.path) : []
            await MainActor.run {
                self.running[id] = nil
                self.desk?.writeChat()
                if tools {
                    self.store.change { $0.setFiles(id, saved) }
                }
                if let done = self.store.team.job(id), !done.isActive {
                    self.onFinished?(done)
                }
                self.pump()
            }
        }
        running[id] = work

        // Nothing works for ever: after the time limit it's stopped, keeping what it wrote.
        DispatchQueue.main.asyncAfter(deadline: .now() + AgentRunner.timeLimit) { [weak self] in
            guard let self = self, self.running[id] != nil, self.store.team.job(id)?.status == .working else { return }
            self.running[id]?.cancel()
            self.store.change { $0.fail(id, problem: "It was still going after \(Int(AgentRunner.timeLimit / 60)) minutes, so it was stopped. What it had written is below.") }
        }
    }

    private static func isFolder(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    // MARK: Claude Code

    private func runWithClaudeCode(id: UUID, path: String?, model: ClaudeModel, system: String, web: Bool, readFolders: [String],
                                   prompt: String, folder: URL) async {
        guard let path = path ?? ClaudeCode.find() else {
            await fail(id, "Couldn't find Claude Code on this Mac. See Settings → Assistant.")
            return
        }
        let feed = AgentFeed(id: id, store: store, folder: folder.path)
        feed.desk = desk
        var problem: String?
        do {
            var errors = ""
            // Claude Code's restricted mode first: there Claude Code itself keeps the agent
            // to its folders and loads no settings files. A Claude Code without that mode
            // stops before it starts, and is run again the other way (see agentArguments).
            for restricted in [true, false] {
                let arguments = ClaudeStream.agentArguments(model: model, system: system, web: web, readFolders: readFolders,
                                                            folder: folder.path, restricted: restricted)
                let outcome = try await ClaudeCode.runLines(path: path, arguments: arguments, prompt: prompt, folder: folder) { line in
                    await feed.take(line)
                }
                errors = outcome.errorOutput
                if Task.isCancelled || outcome.answered || outcome.exitStatus == 0 { break }
            }
            await feed.flush()
            if !Task.isCancelled && !feed.ended {
                // It stopped without a report: say why, as best Claude Code tells us.
                problem = ClaudeStream.isUnknownOption(errors) ? "This Claude Code is too old for agents. In Terminal, run: claude update"
                    : ClaudeStream.codeProblem(errors)
            }
        } catch {
            if !Task.isCancelled {
                problem = "Couldn't start Claude Code: \(error.localizedDescription)"
            }
        }
        // However it ended (finished, stopped part-way, out of time), what it used counts.
        let used = feed.tally.use
        let title = model.title
        let store = self.store
        let usage = assistant.usage
        await MainActor.run {
            guard !used.isEmpty else { return }
            store.change { $0.setUsage(id, tokens: used.tokens, cost: used.cost) }
            usage.record(used, kind: .agent, label: store.team.job(id)?.name ?? "", model: title)
        }
        if let problem = problem {
            await fail(id, problem)
        }
    }

    // MARK: The other engines

    /// Claude with an API key, or Qwen: one answer, from what it knows.
    private func runWithoutTools(id: UUID, system: String, prompt: String, model: ClaudeModel) async {
        await MainActor.run {
            self.store.change { $0.note(id, kind: .note, text: "Thinking it through") }
        }
        let result = await assistant.complete(system: system, prompt: prompt, model: model, json: false, maxTokens: 4000,
                                              purpose: .agent)
        if Task.isCancelled { return }
        switch result {
        case .success(let report):
            let whole = AssistantPrompt.withoutThinking(report)
            await MainActor.run {
                self.store.change { $0.finish(id, report: whole, turns: 1) }
            }
        case .failure(let problem):
            await fail(id, problem.message)
        }
    }

    private func fail(_ id: UUID, _ problem: String) async {
        await MainActor.run {
            self.store.change { $0.fail(id, problem: problem) }
        }
    }
}

/// Takes what Claude Code prints while an agent works and keeps the agent's job up to date.
/// Text arrives a few letters at a time, so it's passed on a few times a second, not
/// letter by letter.
final class AgentFeed {
    private let id: UUID
    private let store: AgentsStore
    private let folder: String
    private var buffer = ""
    private var fresh = false
    private var lastFlush = Date.distantPast
    /// Whether Claude Code said how the job ended.
    private(set) var ended = false
    var desk: TeamDesk?
    /// What the agent has used so far.
    private(set) var tally = TokenTally()
    private var shownTokens = 0

    init(id: UUID, store: AgentsStore, folder: String) {
        self.id = id
        self.store = store
        self.folder = folder
    }

    func take(_ line: String) async {
        tally.take(line: line)
        for event in AgentStream.events(fromLine: line, folder: folder) {
            switch event {
            case .text(let text):
                buffer += text
                if Date().timeIntervalSince(lastFlush) > 0.35 {
                    await flush()
                }
            case .newMessage:
                // Whatever it wrote before was on the way to this: the report starts afresh.
                buffer = ""
                fresh = true
            case .step(let kind, let text, let file):
                await flush()
                await note(kind, text, file)
            case .said(let message):
                await flush()
                let id = self.id
                let desk = self.desk
                let posted = await MainActor.run { desk?.post(message, fromAgent: id) ?? false }
                await note(.note, posted ? "Posted in the team chat" : "Tried to post in the team chat (it has said enough, or the chat is off)", nil)
            case .finished(let report, let turns):
                await flush()
                ended = true
                await finish(report, turns)
            case .failed(let problem):
                await flush()
                ended = true
                await fail(problem)
            }
        }
    }

    /// Passes on what has arrived since the last time.
    func flush() async {
        let tokens = tally.use.tokens
        let counted = tokens != shownTokens
        guard !buffer.isEmpty || fresh || counted else { return }
        let text = buffer
        let afresh = fresh
        buffer = ""
        fresh = false
        shownTokens = tokens
        lastFlush = Date()
        let id = self.id
        let store = self.store
        await MainActor.run {
            store.change { team in
                if !text.isEmpty || afresh {
                    team.write(id, text, fresh: afresh)
                }
                if counted {
                    team.setUsage(id, tokens: tokens, cost: nil)
                }
            }
        }
    }

    private func note(_ kind: AgentStep.Kind, _ text: String, _ file: String?) async {
        let id = self.id
        let store = self.store
        await MainActor.run {
            store.change { $0.note(id, kind: kind, text: text, file: file) }
        }
    }

    private func finish(_ report: String, _ turns: Int) async {
        let id = self.id
        let store = self.store
        await MainActor.run {
            store.change { $0.finish(id, report: report, turns: turns) }
        }
    }

    private func fail(_ problem: String) async {
        let id = self.id
        let store = self.store
        await MainActor.run {
            store.change { $0.fail(id, problem: problem) }
        }
    }
}

/// Runs the team chat: takes messages from you and from agents, keeps the file agents read
/// up to date, and has the chief of staff answer. The chief answers everything you say and
/// anything an agent addresses to @chief, one at a time, and only so often.
final class TeamDesk {
    let store: TeamStore
    private let agents: AgentsStore
    private let assistant: Assistant
    private let settings: AppSettings
    /// What the chief may know when it answers (set by the app): assignments, say.
    var extra: (() -> String)?
    /// Makes the changes in an <agents> block from the chief (set by the app).
    var applyStaff: ((String) -> [String]?)?

    private var answering = false
    private var waiting: [TeamMessage] = []
    private var answered: [Date] = []
    /// The most answers the chief gives in an hour, so a chat can't run away with your plan.
    static let mostAnswers = 30

    init(store: TeamStore, agents: AgentsStore, assistant: Assistant, settings: AppSettings) {
        self.store = store
        self.agents = agents
        self.assistant = assistant
        self.settings = settings
    }

    /// Writes the chat where agents read it. False if it couldn't be written.
    @discardableResult
    func writeChat() -> Bool {
        let text = store.room.transcript(team: agents.team, now: Date())
        do {
            try FileManager.default.createDirectory(at: TeamChat.room, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: TeamChat.file, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Something you typed in the team chat.
    func postFromYou(_ text: String) {
        var posted: TeamMessage?
        store.change { posted = $0.post(text, from: .you) }
        guard let message = posted else { return }
        writeChat()
        ask(message)
    }

    /// Something an agent wrote for the team. False if it wasn't posted.
    func post(_ text: String, fromAgent id: UUID) -> Bool {
        guard settings.agentsTeamChat, let job = agents.team.job(id) else { return false }
        var posted: TeamMessage?
        store.change { posted = $0.post(text, from: .agent(name: job.name, floor: agents.team.floor(of: id)), agent: id) }
        guard let message = posted else { return false }
        writeChat()
        if TeamRoom.wantsChief(message) {
            ask(message)
        }
        return true
    }

    func clear() {
        waiting = []
        store.change { $0.clear() }
        writeChat()
    }

    private func ask(_ message: TeamMessage) {
        waiting.append(message)
        next()
    }

    private func next() {
        guard !answering, !waiting.isEmpty else { return }
        let message = waiting.removeFirst()
        let hourAgo = Date().addingTimeInterval(-3600)
        answered.removeAll { $0 < hourAgo }
        guard answered.count < TeamDesk.mostAnswers, assistant.status.isReady else {
            if message.from == .you {
                let why = assistant.status.isReady ? "I've answered a lot in the last hour, so I'm pausing. Your message is still here for the agents to read."
                    : "I can't answer until the assistant is set up, but agents can still read your message."
                store.change { $0.post(why, from: .chief) }
                writeChat()
            }
            next()
            return
        }
        answering = true
        answered.append(Date())
        let fromYou = message.from == .you
        // Only you can have agents started or stopped: never a message from an agent.
        let canStart = fromYou && assistant.allows(StaffAgent.tag)
        let system = TeamChat.chiefSystem(claude: assistant.engine.isClaude, canStart: canStart)
        let prompt = TeamChat.chiefPrompt(room: store.room, team: agents.team, extra: extra?() ?? "", now: Date())
        let model = assistant.claudeModel
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.assistant.complete(system: system, prompt: prompt, model: model, json: false, maxTokens: 900,
                                                       purpose: .team)
            await MainActor.run {
                self.answering = false
                switch result {
                case .success(let raw):
                    let whole = AssistantPrompt.withoutThinking(raw)
                    var said = AgentBlock.hidden(whole)
                    if canStart, let json = AgentBlock.json(in: whole, tag: StaffAgent.tag), let changes = self.applyStaff?(json), !changes.isEmpty {
                        said += (said.isEmpty ? "" : "\n") + "✓ " + changes.joined(separator: "; ")
                    }
                    self.store.change { $0.post(said, from: .chief) }
                case .failure(let problem):
                    if fromYou {
                        self.store.change { $0.post("(I couldn't answer: \(problem.message))", from: .chief) }
                    }
                }
                self.writeChat()
                self.next()
            }
        }
    }
}
