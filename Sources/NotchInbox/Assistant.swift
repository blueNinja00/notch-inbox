import Combine
import Foundation

/// The assistant. Claude answers by default, through Claude Code on this Mac (signed in to
/// your Claude account) or through Anthropic's API with your key. Qwen is the fully local
/// choice, running on this Mac with Ollama. Which one is set in Settings → Assistant.
final class Assistant: ObservableObject {
    /// One assistant for every screen's notch.
    static let shared = Assistant()

    struct Message: Identifiable, Equatable {
        typealias Role = ChatTurn.Role

        let id = UUID()
        let role: Role
        /// As streamed; shown without any <think> reasoning.
        var raw: String
        var failed = false

        /// Without reasoning or a block asking for a change (the app makes those).
        var text: String {
            role == .assistant ? AgentBlock.hidden(AssistantPrompt.withoutThinking(raw)) : raw
        }
    }

    enum Status: Equatable {
        case checking
        /// Ready, with the name to show, e.g. "Claude Sonnet 5.5" or "qwen3.5:9b".
        case ready(name: String)
        /// Claude Code isn't installed, or isn't anywhere the app can find it.
        case noClaudeCode
        /// No Anthropic API key saved yet.
        case noKey
        /// Ollama isn't running (or isn't installed).
        case noOllama
        /// Ollama is running but has no Qwen model yet.
        case noModel

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var status: Status = .checking
    @Published private(set) var isAnswering = false
    @Published var draft = ""

    @Published var engine: AssistantEngine {
        didSet {
            guard engine != oldValue else { return }
            UserDefaults.standard.set(engine.rawValue, forKey: Assistant.engineKey)
            sharesContext = Assistant.loadSharing(for: engine)
            findsDueDates = Assistant.loadFinding(for: engine)
            status = .checking
            checkSetup()
        }
    }

    @Published var claudeModel: ClaudeModel {
        didSet {
            guard claudeModel != oldValue else { return }
            UserDefaults.standard.set(claudeModel.rawValue, forKey: Assistant.claudeModelKey)
            checkSetup()
        }
    }

    /// Whether the assistant sees your newest emails (sender, subject, time) and notes.
    /// Qwen keeps them on this Mac, so it's on by default there. Claude would send them to
    /// Anthropic, so for Claude it's off until you turn it on.
    @Published var sharesContext: Bool {
        didSet {
            UserDefaults.standard.set(sharesContext, forKey: Assistant.sharingKey(for: engine))
        }
    }

    /// Whether the assistant sees your timetable and may change it when you ask.
    @Published var editsTimetable: Bool {
        didSet { UserDefaults.standard.set(editsTimetable, forKey: Assistant.timetableKey) }
    }

    /// Whether the assistant sees your planner (homework and exams) and may change it when you ask.
    @Published var editsPlanner: Bool {
        didSet { UserDefaults.standard.set(editsPlanner, forKey: Assistant.plannerKey) }
    }

    /// Whether the assistant looks through emails that mention a deadline, to add them to the
    /// planner. Qwen reads them on this Mac. Claude would have them sent to Anthropic, so for
    /// Claude it's off until you turn it on.
    @Published var findsDueDates: Bool {
        didSet {
            guard findsDueDates != oldValue else { return }
            UserDefaults.standard.set(findsDueDates, forKey: Assistant.findingKey(for: engine))
            onFindingChanged?()
        }
    }

    /// "sk-ant-…a1b2" when an API key is saved.
    @Published private(set) var apiKeyHint: String?
    /// Where Claude Code was found.
    @Published private(set) var claudePath: String?

    /// What the assistant may know about your day: newest emails and notes (set by the app).
    var context: (() -> String)?
    /// The timetable in words, and making the changes the assistant asks for (set by the app).
    var timetableDescription: (() -> String)?
    var applyTimetable: ((TimetableAgent.Plan) -> [String])?
    /// The planner in words, and making the changes the assistant asks for (set by the app).
    var plannerDescription: (() -> String)?
    var applyPlanner: ((PlannerAgent.Plan) -> [String])?
    /// Finding due dates in emails was turned on or off, or the assistant became ready.
    var onFindingChanged: (() -> Void)?

    private static let engineKey = "assistantEngine"
    private static let claudeModelKey = "assistantClaudeModel"
    private static let timetableKey = "assistantEditsTimetable"
    private static let plannerKey = "assistantEditsPlanner"
    private let ollama = URL(string: "http://127.0.0.1:11434")!
    private var qwenModel: String?
    private var answering: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let engine = defaults.string(forKey: Assistant.engineKey).flatMap(AssistantEngine.init(rawValue:)) ?? .standard
        self.engine = engine
        claudeModel = defaults.string(forKey: Assistant.claudeModelKey).flatMap(ClaudeModel.init(rawValue:)) ?? .standard
        sharesContext = Assistant.loadSharing(for: engine)
        editsTimetable = defaults.object(forKey: Assistant.timetableKey) == nil ? true : defaults.bool(forKey: Assistant.timetableKey)
        editsPlanner = defaults.object(forKey: Assistant.plannerKey) == nil ? true : defaults.bool(forKey: Assistant.plannerKey)
        findsDueDates = Assistant.loadFinding(for: engine)
        apiKeyHint = APIKeyFile.read().map(APIKeyFile.hint(for:))
    }

    private static func sharingKey(for engine: AssistantEngine) -> String {
        engine.isClaude ? "assistantSharesWithClaude" : "assistantUsesContext"
    }

    private static func loadSharing(for engine: AssistantEngine) -> Bool {
        let key = sharingKey(for: engine)
        guard UserDefaults.standard.object(forKey: key) != nil else { return !engine.isClaude }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func findingKey(for engine: AssistantEngine) -> String {
        engine.isClaude ? "plannerFindsWithClaude" : "plannerFindsWithQwen"
    }

    private static func loadFinding(for engine: AssistantEngine) -> Bool {
        let key = findingKey(for: engine)
        guard UserDefaults.standard.object(forKey: key) != nil else { return !engine.isClaude }
        return UserDefaults.standard.bool(forKey: key)
    }

    var suggestedModel: String {
        AssistantPrompt.suggestedModel(memory: ProcessInfo.processInfo.physicalMemory)
    }

    /// The name on the chip at the top of the assistant, e.g. "Claude Sonnet 5.5".
    var modelName: String {
        engine.isClaude ? "Claude \(claudeModel.title)" : (qwenModel ?? "Qwen")
    }

    // MARK: Setup

    /// Checks the chosen engine can answer: Claude Code installed, an API key saved, or
    /// Ollama running with a Qwen model.
    func checkSetup() {
        let engine = self.engine
        Task { [weak self] in
            guard let self = self else { return }
            var path: String?
            var qwen: String?
            let status: Status
            switch engine {
            case .claudeCode:
                path = await Task.detached(priority: .userInitiated) { ClaudeCode.find() }.value
                status = path == nil ? .noClaudeCode : .ready(name: "")
            case .claudeAPI:
                status = APIKeyFile.read() == nil ? .noKey : .ready(name: "")
            case .qwen:
                let found = await self.findQwen()
                status = found.status
                qwen = found.model
            }
            let foundPath = path
            let foundQwen = qwen
            await MainActor.run {
                guard self.engine == engine else { return }
                if engine == .claudeCode {
                    self.claudePath = foundPath
                }
                if engine == .qwen {
                    self.qwenModel = foundQwen
                }
                self.apiKeyHint = APIKeyFile.read().map(APIKeyFile.hint(for:))
                let shown: Status = status.isReady ? .ready(name: self.modelName) : status
                if self.status != shown {
                    self.status = shown
                    if shown.isReady {
                        self.onFindingChanged?()
                    }
                }
            }
        }
    }

    /// Saves a pasted API key. False if it doesn't look like one.
    @discardableResult
    func saveAPIKey(_ typed: String) -> Bool {
        guard APIKeyFile.save(typed) else { return false }
        apiKeyHint = APIKeyFile.read().map(APIKeyFile.hint(for:))
        checkSetup()
        return true
    }

    func removeAPIKey() {
        APIKeyFile.delete()
        apiKeyHint = nil
        checkSetup()
    }

    private func findQwen() async -> (status: Status, model: String?) {
        var request = URLRequest(url: ollama.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return (.noOllama, nil)
        }
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        let names = (try? JSONDecoder().decode(Tags.self, from: data))?.models.map { $0.name } ?? []
        guard let model = AssistantPrompt.pickModel(from: names) else { return (.noModel, nil) }
        return (.ready(name: model), model)
    }

    // MARK: Chatting

    func send(_ typed: String? = nil) {
        let question = (typed ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering, status.isReady else { return }
        if typed == nil {
            draft = ""
        }

        let timetable = editsTimetable ? (timetableDescription?() ?? "") : ""
        let planner = editsPlanner ? (plannerDescription?() ?? "") : ""
        let shared = [sharesContext ? (context?() ?? "") : "", timetable, planner].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let canEdit = !timetable.isEmpty
        let canPlan = !planner.isEmpty
        var history = messages.map { (role: $0.role, text: $0.text, failed: $0.failed) }
        history.append((role: .user, text: question, failed: false))
        let turns = ClaudeStream.turns(from: history)

        messages.append(Message(role: .user, raw: question))
        messages.append(Message(role: .assistant, raw: ""))
        isAnswering = true

        let engine = self.engine
        let model = claudeModel
        answering = Task { [weak self] in
            guard let self = self else { return }
            switch engine {
            case .claudeCode:
                await self.askClaudeCode(model: model, context: shared, turns: turns, timetable: canEdit, planner: canPlan)
            case .claudeAPI:
                let system = AssistantPrompt.system(now: Date(), context: shared, claude: true, timetable: canEdit, planner: canPlan)
                await self.askAnthropic(model: model, system: system, turns: turns)
            case .qwen:
                let system = AssistantPrompt.system(now: Date(), context: shared, timetable: canEdit, planner: canPlan)
                await self.askQwen(system: system, turns: turns)
            }
        }
    }

    /// Stops the answer where it is.
    func stop() {
        answering?.cancel()
    }

    func newChat() {
        stop()
        messages = []
        draft = ""
    }

    // MARK: Claude Code

    private func askClaudeCode(model: ClaudeModel, context: String, turns: [ChatTurn], timetable: Bool, planner: Bool) async {
        guard let path = claudePath ?? ClaudeCode.find() else {
            await finish(problem: "Couldn't find Claude Code on this Mac. See Settings → Assistant.")
            return
        }
        // The context goes in with the question, so it never appears on a command line.
        let system = AssistantPrompt.system(now: Date(), context: "", claude: true, timetable: timetable, planner: planner)
        let prompt = ClaudeStream.codeInput(context: context, turns: turns)

        var problem: String?
        var streamed = false
        do {
            for compatible in [false, true] {
                problem = nil
                let outcome = try await ClaudeCode.run(
                    path: path,
                    arguments: ClaudeStream.codeArguments(model: model, system: system, compatible: compatible),
                    prompt: prompt
                ) { piece in
                    switch piece {
                    case .text(let text):
                        streamed = true
                        await MainActor.run { self.appendToAnswer(text) }
                    case .finished(let whole):
                        // An older Claude Code that doesn't stream says it all at the end.
                        if !streamed && !whole.isEmpty {
                            streamed = true
                            await MainActor.run { self.appendToAnswer(whole) }
                        }
                    case .failed(let reason):
                        problem = reason
                    case .done:
                        break
                    }
                }
                if Task.isCancelled { break }
                // An older Claude Code that doesn't know the newer options: ask again without them.
                if !compatible && !outcome.answered && ClaudeStream.isUnknownOption(outcome.errorOutput) {
                    continue
                }
                if problem == nil && !streamed {
                    problem = ClaudeStream.codeProblem(outcome.errorOutput)
                }
                break
            }
        } catch {
            if !Task.isCancelled {
                problem = "Couldn't start Claude Code: \(error.localizedDescription)"
            }
        }
        await finish(problem: problem)
    }

    // MARK: Anthropic API

    private func askAnthropic(model: ClaudeModel, system: String, turns: [ChatTurn]) async {
        guard let key = APIKeyFile.read() else {
            await finish(problem: "Add your Anthropic API key in Settings → Assistant.")
            return
        }
        var request = URLRequest(url: ClaudeStream.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeStream.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120
        request.httpBody = ClaudeStream.apiBody(model: model, system: system, turns: turns)

        var problem: String?
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                var body = ""
                for try await line in bytes.lines {
                    body += line
                    if body.count > 8000 { break }
                }
                problem = ClaudeStream.apiProblem(status: code, body: body)
            } else {
                reading: for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    switch ClaudeStream.apiPiece(fromLine: line) {
                    case .text(let text)?:
                        await MainActor.run { self.appendToAnswer(text) }
                    case .failed(let reason)?:
                        problem = reason
                        break reading
                    case .done?:
                        break reading
                    case .finished?, nil:
                        continue
                    }
                }
            }
        } catch {
            if !Task.isCancelled {
                problem = "Couldn't reach Anthropic. Check your internet connection."
            }
        }
        await finish(problem: problem)
    }

    // MARK: Qwen with Ollama

    private func askQwen(system: String, turns: [ChatTurn]) async {
        guard let model = qwenModel else {
            await finish(problem: "Qwen isn't set up yet.")
            return
        }
        var request = URLRequest(url: ollama.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let history = [["role": "system", "content": system]] + turns.map { ["role": $0.role.rawValue, "content": $0.text] }
        let body: [String: Any] = [
            "model": model,
            "messages": history,
            "stream": true,
            "think": false,
            "keep_alive": "15m",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var problem: String?
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 {
                problem = "Ollama answered \(code). Is \(model) still downloaded?"
            } else {
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let chunk = AssistantPrompt.chunk(from: line) else { continue }
                    if let error = chunk.error {
                        problem = error
                        break
                    }
                    if let piece = chunk.message?.content, !piece.isEmpty {
                        await MainActor.run { self.appendToAnswer(piece) }
                    }
                    if chunk.done == true { break }
                }
            }
        } catch {
            if !Task.isCancelled {
                problem = "Couldn't reach Ollama. Is it running?"
            }
        }
        await finish(problem: problem)
    }

    // MARK: Answers

    private func appendToAnswer(_ piece: String) {
        guard let last = messages.indices.last, messages[last].role == .assistant else { return }
        messages[last].raw += piece
    }

    private func finish(problem: String?) async {
        await MainActor.run {
            self.isAnswering = false
            guard let last = self.messages.indices.last, self.messages[last].role == .assistant else { return }
            if let problem = problem {
                if self.messages[last].text.isEmpty {
                    self.messages[last].raw = problem
                    self.messages[last].failed = true
                } else {
                    // Keep what was written before it went wrong.
                    self.messages[last].raw += "\n\n(" + problem + ")"
                }
                self.checkSetup()
            } else if self.messages[last].text.isEmpty && !self.messages[last].raw.contains(TimetableAgent.openTag)
                        && !self.messages[last].raw.contains(PlannerAgent.openTag) {
                self.messages[last].raw = "(Stopped)"
            }
            // The assistant asked to change the timetable or the planner: make the changes,
            // then say what changed.
            guard problem == nil, !Task.isCancelled else { return }
            let raw = self.messages[last].raw
            var notes: [String] = []
            if raw.contains(TimetableAgent.closeTag) {
                let found = TimetableAgent.extract(from: raw)
                if let plan = found.plan, let apply = self.applyTimetable {
                    notes.append(Assistant.note("Timetable updated", changes: apply(plan), nothing: "(The timetable already had that.)"))
                } else if found.plan == nil {
                    notes.append("(I tried to change your timetable, but the change didn't come through right. Ask again?)")
                }
            }
            if raw.contains(PlannerAgent.closeTag) {
                let found = PlannerAgent.extract(from: raw)
                if let plan = found.plan, let apply = self.applyPlanner {
                    notes.append(Assistant.note("Planner updated", changes: apply(plan), nothing: "(The planner already had that.)"))
                } else if found.plan == nil {
                    notes.append("(I tried to change your planner, but the change didn't come through right. Ask again?)")
                }
            }
            if !notes.isEmpty {
                let said = AgentBlock.hidden(AssistantPrompt.withoutThinking(raw))
                self.messages[last].raw = (said.isEmpty ? "" : said + "\n\n") + notes.joined(separator: "\n")
            }
        }
    }

    /// "✓ Timetable updated: Tue 5 pm: Soccer; Wed 6 pm: cleared".
    private static func note(_ heading: String, changes: [String], nothing: String) -> String {
        guard !changes.isEmpty else { return nothing }
        return "✓ \(heading): " + changes.prefix(12).joined(separator: "; ") + (changes.count > 12 ? "; and \(changes.count - 12) more" : "")
    }

    // MARK: One question, one answer

    /// What went wrong, in words.
    struct Problem: Error {
        let message: String
    }

    /// Asks once and waits for the whole answer, outside the chat: for jobs behind the scenes,
    /// like finding due dates in emails. Claude answers with its fastest model.
    func complete(system: String, prompt: String) async -> Result<String, Problem> {
        switch engine {
        case .claudeCode:
            return await completeWithClaudeCode(system: system, prompt: prompt)
        case .claudeAPI:
            return await completeWithAnthropic(system: system, prompt: prompt)
        case .qwen:
            return await completeWithQwen(system: system, prompt: prompt)
        }
    }

    private func completeWithClaudeCode(system: String, prompt: String) async -> Result<String, Problem> {
        guard let path = claudePath ?? ClaudeCode.find() else {
            return .failure(Problem(message: "Couldn't find Claude Code on this Mac."))
        }
        var streamed = ""
        var whole = ""
        var problem: String?
        do {
            for compatible in [false, true] {
                streamed = ""
                whole = ""
                problem = nil
                let outcome = try await ClaudeCode.run(
                    path: path,
                    arguments: ClaudeStream.codeArguments(model: .haiku, system: system, compatible: compatible),
                    prompt: prompt
                ) { piece in
                    switch piece {
                    case .text(let text): streamed += text
                    case .finished(let text): whole = text
                    case .failed(let reason): problem = reason
                    case .done: break
                    }
                }
                if !compatible && !outcome.answered && ClaudeStream.isUnknownOption(outcome.errorOutput) {
                    continue
                }
                if problem == nil && streamed.isEmpty && whole.isEmpty {
                    problem = ClaudeStream.codeProblem(outcome.errorOutput)
                }
                break
            }
        } catch {
            problem = "Couldn't start Claude Code: \(error.localizedDescription)"
        }
        if let problem = problem {
            return .failure(Problem(message: problem))
        }
        return .success(whole.isEmpty ? streamed : whole)
    }

    private func completeWithAnthropic(system: String, prompt: String) async -> Result<String, Problem> {
        guard let key = APIKeyFile.read() else {
            return .failure(Problem(message: "Add your Anthropic API key in Settings → Assistant."))
        }
        var request = URLRequest(url: ClaudeStream.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeStream.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 90
        request.httpBody = ClaudeStream.apiBody(model: .haiku, system: system, turns: [ChatTurn(role: .user, text: prompt)],
                                                maxTokens: 1500, stream: false)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                return .failure(Problem(message: ClaudeStream.apiProblem(status: code, body: String(decoding: data.prefix(8000), as: UTF8.self))))
            }
            guard let text = ClaudeStream.apiText(from: data) else {
                return .failure(Problem(message: "Claude's answer couldn't be read."))
            }
            return .success(text)
        } catch {
            return .failure(Problem(message: "Couldn't reach Anthropic. Check your internet connection."))
        }
    }

    private func completeWithQwen(system: String, prompt: String) async -> Result<String, Problem> {
        guard let model = qwenModel else {
            return .failure(Problem(message: "Qwen isn't set up yet."))
        }
        var request = URLRequest(url: ollama.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            "stream": false,
            "think": false,
            "format": "json",
            "keep_alive": "5m",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 {
                return .failure(Problem(message: "Ollama answered \(code). Is \(model) still downloaded?"))
            }
            let chunk = AssistantPrompt.chunk(from: String(decoding: data, as: UTF8.self))
            if let error = chunk?.error {
                return .failure(Problem(message: error))
            }
            guard let text = chunk?.message?.content, !text.isEmpty else {
                return .failure(Problem(message: "Qwen's answer couldn't be read."))
            }
            return .success(text)
        } catch {
            return .failure(Problem(message: "Couldn't reach Ollama. Is it running?"))
        }
    }
}
