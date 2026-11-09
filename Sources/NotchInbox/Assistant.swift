import Combine
import Foundation

/// The assistant: Qwen running on this Mac through Ollama (http://127.0.0.1:11434).
/// Nothing you ask, and none of the email or notes it's given, leaves the Mac.
final class Assistant: ObservableObject {
    /// One assistant for every screen's notch.
    static let shared = Assistant()

    struct Message: Identifiable, Equatable {
        enum Role: String {
            case user
            case assistant
        }

        let id = UUID()
        let role: Role
        /// As streamed; shown without any <think> reasoning.
        var raw: String
        var failed = false

        var text: String {
            role == .assistant ? AssistantPrompt.withoutThinking(raw) : raw
        }
    }

    enum Status: Equatable {
        case checking
        case ready(model: String)
        /// Ollama isn't running (or isn't installed).
        case noOllama
        /// Ollama is running but has no Qwen model yet.
        case noModel
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var status: Status = .checking
    @Published private(set) var isAnswering = false
    @Published var draft = ""
    /// Whether Qwen sees your newest emails and notes.
    @Published var usesContext = true {
        didSet { UserDefaults.standard.set(usesContext, forKey: Assistant.contextKey) }
    }

    /// What Qwen may know about your day (set by the app).
    var context: (() -> String)?

    private static let contextKey = "assistantUsesContext"
    private let server = URL(string: "http://127.0.0.1:11434")!
    private var answering: Task<Void, Never>?

    init() {
        if UserDefaults.standard.object(forKey: Assistant.contextKey) != nil {
            usesContext = UserDefaults.standard.bool(forKey: Assistant.contextKey)
        }
    }

    var suggestedModel: String {
        AssistantPrompt.suggestedModel(memory: ProcessInfo.processInfo.physicalMemory)
    }

    // MARK: Ollama

    /// Asks Ollama which models it has and picks the newest Qwen.
    func checkSetup() {
        Task { [weak self] in
            guard let self = self else { return }
            let status = await self.findModel()
            await MainActor.run {
                self.status = status
            }
        }
    }

    private func findModel() async -> Status {
        var request = URLRequest(url: server.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return .noOllama
        }
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        let names = (try? JSONDecoder().decode(Tags.self, from: data))?.models.map { $0.name } ?? []
        guard let model = AssistantPrompt.pickModel(from: names) else { return .noModel }
        return .ready(model: model)
    }

    // MARK: Chatting

    func send(_ typed: String? = nil) {
        let question = (typed ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering, case .ready(let model) = status else { return }
        if typed == nil {
            draft = ""
        }

        let system = AssistantPrompt.system(now: Date(), context: usesContext ? (context?() ?? "") : "")
        var history: [[String: String]] = [["role": "system", "content": system]]
        for message in messages.suffix(20) where !message.failed {
            history.append(["role": message.role.rawValue, "content": message.text])
        }
        history.append(["role": "user", "content": question])

        messages.append(Message(role: .user, raw: question))
        messages.append(Message(role: .assistant, raw: ""))
        isAnswering = true

        answering = Task { [weak self] in
            await self?.stream(model: model, history: history)
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

    private func stream(model: String, history: [[String: String]]) async {
        var request = URLRequest(url: server.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
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
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                problem = "Ollama answered \(status). Is \(model) still downloaded?"
            } else {
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let chunk = AssistantPrompt.chunk(from: line) else { continue }
                    if let error = chunk.error {
                        problem = error
                        break
                    }
                    if let piece = chunk.message?.content, !piece.isEmpty {
                        await MainActor.run {
                            self.appendToAnswer(piece)
                        }
                    }
                    if chunk.done == true { break }
                }
            }
        } catch {
            if !Task.isCancelled {
                problem = "Couldn't reach Ollama. Is it running?"
            }
        }

        let failure = problem
        await MainActor.run {
            self.finishAnswer(problem: failure)
        }
    }

    private func appendToAnswer(_ piece: String) {
        guard let last = messages.indices.last, messages[last].role == .assistant else { return }
        messages[last].raw += piece
    }

    private func finishAnswer(problem: String?) {
        isAnswering = false
        guard let last = messages.indices.last, messages[last].role == .assistant else { return }
        if let problem = problem {
            messages[last].raw = problem
            messages[last].failed = true
            checkSetup()
        } else if messages[last].text.isEmpty {
            messages[last].raw = "(Stopped)"
        }
    }
}
