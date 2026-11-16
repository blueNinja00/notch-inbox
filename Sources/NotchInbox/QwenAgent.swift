import Foundation

/// A Qwen agent: works through its job over many turns with Ollama on this Mac, using the
/// tools in its toolbox (the app does each one, by the toolbox's rules), and finishes with a
/// report. Its web searches and the pages it reads go through Ollama's web search, with your
/// Ollama key; everything else stays on this Mac.
final class QwenAgent {
    static let chat = URL(string: "http://127.0.0.1:11434/api/chat")!
    static let webSearch = URL(string: "https://ollama.com/api/web_search")!
    static let webFetch = URL(string: "https://ollama.com/api/web_fetch")!
    /// The most turns of tool use before it's asked for its report.
    static let mostTurns = 30

    private let model: String
    private let toolbox: AgentToolbox
    private let webKey: String?
    private let contextSize: Int
    /// Each step it takes, for the room (the same feed Claude agents use).
    private let onEvent: (AgentStream.Event) async -> Void
    /// What it has used so far, after every turn.
    private let onUsage: (TokenUse) async -> Void
    private(set) var used = TokenUse()

    enum Outcome {
        case report(String, turns: Int)
        case problem(String)
    }

    init(model: String, toolbox: AgentToolbox, webKey: String?, contextSize: Int,
         onEvent: @escaping (AgentStream.Event) async -> Void, onUsage: @escaping (TokenUse) async -> Void) {
        self.model = model
        self.toolbox = toolbox
        self.webKey = webKey
        self.contextSize = contextSize
        self.onEvent = onEvent
        self.onUsage = onUsage
    }

    func run(system: String, prompt: String) async -> Outcome {
        var messages: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        var nudged = false
        for turn in 1...(QwenAgent.mostTurns + 1) {
            if Task.isCancelled {
                return .problem("Stopped.")
            }
            let last = turn > QwenAgent.mostTurns
            if last {
                messages.append(["role": "user", "content": "That's all the looking there's time for. Write your report now, from what you've found."])
            }
            AgentToolbox.trim(&messages, budget: AgentToolbox.budget(contextSize))
            let reply: AgentToolbox.Reply
            switch await ask(messages, tools: !last) {
            case .failure(let refusal): return .problem(refusal.message)
            case .success(let answer): reply = answer
            }
            used.input += reply.promptTokens
            used.output += reply.outputTokens
            await onUsage(used)

            if reply.calls.isEmpty {
                let report = AssistantPrompt.withoutThinking(reply.content)
                if report.isEmpty && !nudged {
                    nudged = true
                    messages.append(["role": "assistant", "content": reply.content])
                    messages.append(["role": "user", "content": "Now write your report: it's all the student will read."])
                    continue
                }
                guard !report.isEmpty else { return .problem("Qwen stopped without writing a report.") }
                return .report(report, turns: turn)
            }
            var said: [String: Any] = ["role": "assistant", "content": reply.content]
            if !reply.rawCalls.isEmpty {
                said["tool_calls"] = reply.rawCalls
            }
            messages.append(said)
            for call in reply.calls {
                if Task.isCancelled {
                    return .problem("Stopped.")
                }
                let result = await perform(call)
                messages.append(["role": "tool", "tool_name": call.name, "content": result])
            }
        }
        return .problem("Qwen stopped without writing a report.")
    }

    // MARK: Tools

    private func perform(_ call: AgentToolbox.Call) async -> String {
        guard let tool = call.tool, toolbox.tools.contains(tool) else {
            await onEvent(toolbox.event(for: call))
            return "There's no tool called \(call.name). You can use: " + toolbox.tools.map(\.rawValue).joined(separator: ", ") + "."
        }
        let event = toolbox.event(for: call)
        await onEvent(event)
        switch tool {
        case .listFiles:
            return toolbox.list(call.text("path"))
        case .readFile:
            return toolbox.read(call.text("path"), from: call.number("start_line") ?? 1)
        case .writeFile:
            // A note to the team is posted in the team chat (by the feed), not kept as a file.
            if case .said = event {
                return "Posted in the team chat."
            }
            return toolbox.write(call.text("path"), content: call.text("content")).text
        case .webSearch:
            return await search(call.text("query"))
        case .webFetch:
            return await fetch(call.text("url"))
        }
    }

    private func search(_ query: String) async -> String {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return "Give some words to search for." }
        guard let data = await askWeb(QwenAgent.webSearch, body: ["query": words, "max_results": 6]) else {
            return problemWithWeb
        }
        return AgentToolbox.searchText(from: data, query: words)
    }

    private func fetch(_ address: String) async -> String {
        guard let url = AgentToolbox.webAddress(address) else { return "That isn't a web address. It needs to start with https://" }
        guard let data = await askWeb(QwenAgent.webFetch, body: ["url": url.absoluteString]) else {
            return problemWithWeb
        }
        return AgentToolbox.pageText(from: data, url: url.absoluteString)
    }

    private var problemWithWeb = "The web didn't answer. Carry on with what you have."

    /// Asks Ollama's web service. Nil if it didn't work (no key, no internet, a refused key).
    private func askWeb(_ url: URL, body: [String: Any]) async -> Data? {
        guard toolbox.web, let key = webKey else {
            problemWithWeb = "The web isn't available for this job. Work from what you know."
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                problemWithWeb = "The web search key was refused, so the web isn't available. Work from what you know."
                await onEvent(.step(.problem, "Ollama refused the web search key (see Settings → Assistant)", file: nil))
                return nil
            }
            guard code == 200 else {
                problemWithWeb = "The web didn't answer (\(code)). Carry on with what you have."
                return nil
            }
            return data
        } catch {
            problemWithWeb = "The web couldn't be reached. Carry on with what you have."
            return nil
        }
    }

    // MARK: Ollama

    private func ask(_ messages: [[String: Any]], tools: Bool) async -> Result<AgentToolbox.Reply, AgentToolbox.Refusal> {
        var request = URLRequest(url: QwenAgent.chat)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A long turn on a small Mac can take a while; the runner's time limit still applies.
        request.timeoutInterval = 600
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "think": false,
            "keep_alive": "10m",
            "options": ["num_ctx": contextSize],
        ]
        if tools {
            body["tools"] = toolbox.definitions
        }
        guard let sent = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(AgentToolbox.Refusal(message: "The job couldn't be sent to Qwen."))
        }
        request.httpBody = sent
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            let reply = AgentToolbox.reply(from: data)
            if code != 200 {
                return .failure(AgentToolbox.Refusal(message: QwenAgent.problem(code: code, said: reply?.error ?? "", model: model)))
            }
            guard let answer = reply else {
                return .failure(AgentToolbox.Refusal(message: "Qwen's answer couldn't be read."))
            }
            if let error = answer.error {
                return .failure(AgentToolbox.Refusal(message: QwenAgent.problem(code: code, said: error, model: model)))
            }
            return .success(answer)
        } catch {
            return .failure(AgentToolbox.Refusal(message: Task.isCancelled ? "Stopped." : "Couldn't reach Ollama. Is it running?"))
        }
    }

    /// What Ollama's complaint means, and what to do about it.
    static func problem(code: Int, said: String, model: String) -> String {
        let lower = said.lowercased()
        if lower.contains("does not support tools") {
            return "\(model) can't use tools, so it can't be an agent. In Terminal, download a newer Qwen: ollama pull qwen3.5:9b"
        }
        if lower.contains("not found") {
            return "\(model) isn't downloaded any more. See Settings → Assistant."
        }
        if code == 0 || said.isEmpty {
            return "Ollama answered \(code). Is it still running?"
        }
        return "Ollama said: \(AgentStream.shorten(said, to: 160))"
    }
}
