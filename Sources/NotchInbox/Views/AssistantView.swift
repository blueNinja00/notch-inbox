import AppKit
import SwiftUI

/// The assistant: chat with Claude (or Qwen, on this Mac). Expand it for more room.
struct AssistantView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant
    let expanded: Bool
    @FocusState private var typing: Bool

    init(model: NotchModel, assistant: Assistant, expanded: Bool) {
        self.model = model
        self.assistant = assistant
        self.expanded = expanded
    }

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "sparkles", title: "Assistant") {
                    if case .ready(let name) = assistant.status {
                        Button(action: { model.openSettings(.assistant) }) {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(assistant.engine.title + ". Click to change in Settings.")
                    }
                }
            } trailing: {
                HStack(spacing: 2) {
                    IconButton(symbol: HomeTile.agents.symbol, label: "The agent room: jobs handed to agents", action: { model.openAgents() })
                    IconButton(symbol: "square.and.pencil", label: "New chat", action: {
                        assistant.newChat()
                        typing = true
                    })
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make smaller" : "Expand",
                               action: { expanded ? model.back() : model.expandAssistant() })
                    SettingsButton(model: model, section: .assistant)
                }
                .padding(.trailing, 4)
            }

            switch assistant.status {
            case .ready:
                chat
            case .checking:
                Text(assistant.engine == .claudeCode ? "Looking for Claude Code on this Mac…"
                     : assistant.engine == .qwen ? "Looking for Qwen on this Mac…" : "Getting Claude ready…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noOllama, .noModel:
                AssistantSetup(assistant: assistant)
            case .noClaudeCode, .noKey:
                ClaudeSetup(model: model, assistant: assistant)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear { assistant.checkSetup() }
    }

    private var chat: some View {
        VStack(spacing: 8) {
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        if assistant.messages.isEmpty {
                            Suggestions(assistant: assistant)
                        }
                        ForEach(assistant.messages) { message in
                            ChatBubble(message: message, thinking: assistant.isAnswering && message.id == assistant.messages.last?.id,
                                       doing: assistant.activity, target: model.typingTarget,
                                       typeIt: { model.typeIntoDocument(message.text) })
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onChange(of: assistant.messages) { messages in
                    if let last = messages.last {
                        scroller.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let note = model.typingNote {
                TypingNote(text: note, settings: { model.openSettings(.assistant) }, dismiss: { model.typingNote = nil })
            }
            if let attachment = assistant.attachment {
                AttachmentChip(attachment: attachment, claude: assistant.engine.isClaude, remove: { assistant.attachment = nil })
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask \(assistant.engine.name) anything…", text: $assistant.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...5)
                    .focused($typing)
                    .onSubmit { assistant.send() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))

                if assistant.isAnswering {
                    IconButton(symbol: "stop.fill", label: "Stop", size: 32, tint: Theme.text, action: { assistant.stop() })
                } else {
                    IconButton(symbol: "arrow.up", label: "Send (Return)", size: 32, tint: Theme.text, action: { assistant.send() })
                }
            }

            HStack(spacing: 6) {
                Toggle(isOn: $assistant.sharesContext) {
                    Text(assistant.engine.isClaude
                         ? "Let Claude see my newest email subjects and notes (sent to Anthropic with your question)"
                         : "Let Qwen see my newest emails and notes (they stay on this Mac)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Text from the document you're working in, to ask about or have rewritten.
                SmallPill(title: "Use Selection", symbol: "text.cursor", action: { model.useSelection() })
                    .help(AssistantView.selectionHelp(app: model.typingTarget, claude: assistant.engine.isClaude))
                SmallPill(title: "Use Copied", symbol: "doc.on.clipboard", action: { model.useClipboard() })
                    .help("Attach the text on your clipboard to your next question")
            }
        }
        .padding(.top, 6)
        .onAppear { typing = true }
    }

    static func selectionHelp(app: String?, claude: Bool) -> String {
        let place = app.map { "in \($0)" } ?? "in the app you were in"
        return "Attach what you've selected \(place) to your next question" + (claude ? ". It's sent to Anthropic with the question." : ". It stays on this Mac.")
    }
}

/// Text from a document, waiting to go with your next question.
struct AttachmentChip: View {
    let attachment: DocumentSelection
    let claude: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "paperclip")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text(attachment.summary)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .fixedSize()
            Text(DocumentText.preview(attachment.text))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            IconButton(symbol: "xmark", label: "Don't attach it", size: 22, action: remove)
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
        .help(claude ? "This goes to Anthropic with your next question. Ask about it, or ask for it to be rewritten."
                     : "This goes with your next question, and stays on this Mac.")
    }
}

/// How the last go at typing into a document, or reading a selection, went.
struct TypingNote: View {
    let text: String
    let settings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if text.contains("Accessibility") {
                SmallPill(title: "Settings", symbol: "gearshape", action: settings)
            }
            IconButton(symbol: "xmark", label: "Dismiss", size: 22, action: dismiss)
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
    }
}

/// One message: yours on the right, the assistant's on the left.
struct ChatBubble: View {
    let message: Assistant.Message
    let thinking: Bool
    /// What it's doing before it answers ("Searching the web for …"), for the answer being written.
    var doing: String? = nil
    /// The app a finished answer can be typed into ("Pages"), and what types it.
    var target: String? = nil
    var typeIt: (() -> Void)? = nil

    var body: some View {
        let mine = message.role == .user
        let text = message.text
        let busy = thinking ? doing : nil
        let finished = !mine && !thinking && !message.failed && !text.isEmpty

        HStack(alignment: .bottom, spacing: 4) {
            if mine { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty && thinking {
                    Text(busy ?? "Thinking…")
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text(ChatBubble.formatted(text))
                        .foregroundStyle(message.failed ? Theme.tertiary : (mine ? Theme.text : Theme.body))
                        .textSelection(.enabled)
                    if let busy = busy {
                        // Looking something up part-way through its answer.
                        Text(busy)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                    if let attachment = message.attachment {
                        // What went with this question.
                        Label(attachment.summary, systemImage: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .font(.system(size: 13))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(mine ? Theme.raised : Theme.surface))
            if finished {
                BubbleActions(text: text, target: target, typeIt: typeIt)
            }
            if !mine { Spacer(minLength: finished ? 8 : 60) }
        }
    }

    /// Bold, italics, code and links from the answer's Markdown, keeping its line breaks.
    /// Only links to the web can be clicked.
    static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        return RichText.webLinksOnly(parsed)
    }
}

/// Beside a finished answer: copy it, or have it typed into the document you were in.
struct BubbleActions: View {
    let text: String
    let target: String?
    let typeIt: (() -> Void)?
    @State var copied = false

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: "Copy this answer", size: 24, tint: Theme.tertiary, action: copy)
            if let typeIt = typeIt {
                IconButton(symbol: "keyboard", label: BubbleActions.typeHelp(target), size: 24, tint: Theme.tertiary, action: typeIt)
            }
        }
    }

    static func typeHelp(_ target: String?) -> String {
        guard let target = target else { return "Type this into the document you were in, where your cursor is" }
        return "Type this into \(target), where your cursor is (it replaces anything selected)"
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}

/// Ideas to start with when the chat is empty.
struct Suggestions: View {
    @ObservedObject var assistant: Assistant

    /// Something to ask. The ones that end mid-sentence go in the box for you to finish.
    private struct Idea: Identifiable {
        let text: String
        var finish = false
        var id: String { text }
    }

    private let ideas = [
        Idea(text: "What's due soon?"),
        Idea(text: "How are my marks going?"),
        Idea(text: "What have I got tomorrow?"),
        Idea(text: "Explain ", finish: true),
        Idea(text: "Get an agent to research ", finish: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(intro)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(ideas) { idea in
                    Button(action: { pick(idea) }) {
                        Text(idea.finish ? idea.text.trimmingCharacters(in: .whitespaces) + "…" : idea.text)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(Theme.raised))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ idea: Idea) {
        if idea.finish {
            assistant.draft = idea.text
        } else {
            assistant.send(idea.text)
        }
    }

    private var intro: String {
        if assistant.searchesWeb {
            return "Your chief of staff. Ask anything: it can look things up on the web, keep your planner, timetable, assignments and bookmarks in order, and hand bigger jobs to agents."
        }
        if assistant.engine.isClaude {
            return "Your chief of staff. Ask anything: it can keep your planner, timetable, assignments and bookmarks in order, and hand bigger jobs to agents."
        }
        return "Your chief of staff. Ask anything: it can keep your planner, timetable, assignments and bookmarks in order. Qwen runs on this Mac."
    }
}

/// How to get Qwen running: install Ollama, download a model, check again.
struct AssistantSetup: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        let noOllama = assistant.status == .noOllama

        VStack(alignment: .leading, spacing: 10) {
            Text(noOllama ? "Set up Qwen on this Mac" : "One more step: download Qwen")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if noOllama {
                SetupStep(number: 1, text: "Install Ollama from ollama.com (free), then open it.")
            }
            SetupStep(number: noOllama ? 2 : 1,
                      text: "In Terminal, run this. It downloads the Qwen model that suits your Mac's memory (several GB, so use Wi-Fi):")
            CommandBox(command: "ollama pull \(assistant.suggestedModel)")
            SetupStep(number: noOllama ? 3 : 2, text: "When it's finished, click Check Again.")
            HStack(spacing: 8) {
                PillButton(title: "Check Again", prominent: true, action: { assistant.checkSetup() })
                PillButton(title: "Use Claude instead", action: { assistant.engine = .claudeCode })
            }
            Text("Qwen runs on your Mac, and nothing you ask is sent anywhere.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 10)
        .padding(.leading, 6)
    }
}

/// What Claude needs before it can answer: Claude Code installed, or an API key.
struct ClaudeSetup: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant

    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if assistant.status == .noClaudeCode {
                Text("Set up Claude")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                SetupStep(number: 1, text: "Claude answers through Claude Code, signed in to your Claude account. In Terminal, install it:")
                CommandBox(command: ClaudeSetup.installCommand)
                SetupStep(number: 2, text: "Then type claude, press Return and sign in. When it's ready, click Check Again.")
                HStack(spacing: 8) {
                    PillButton(title: "Check Again", prominent: true, action: { assistant.checkSetup() })
                    PillButton(title: "Use an API key instead", action: {
                        assistant.engine = .claudeAPI
                        model.openSettings(.assistant)
                    })
                }
            } else {
                Text("Add your Anthropic API key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Paste a key from console.anthropic.com in Settings, or switch to your Claude plan there.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.body)
                PillButton(title: "Open Assistant Settings", prominent: true, action: { model.openSettings(.assistant) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 10)
        .padding(.leading, 6)
    }
}

/// A numbered step in a setup guide.
struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.secondary))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A Terminal command to copy.
struct CommandBox: View {
    let command: String
    @State var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
            IconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: "Copy", size: 28, action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            })
        }
    }
}

/// A rounded button: white when it's the main thing to do, grey otherwise.
struct PillButton: View {
    let title: String
    var prominent = false
    var action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(prominent ? Theme.onAccent : Theme.text2)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(prominent ? Theme.accent.opacity(hovering ? 1 : 0.92) : (hovering ? Theme.hover : Theme.raised)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The assistant on the primary menu.
struct AssistantToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant
    @State var hovering = false

    var body: some View {
        let last = assistant.messages.last { $0.role == .assistant && !$0.failed && !$0.text.isEmpty }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ToolIcon(symbol: "sparkles")
                Text("Assistant")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(last.map { $0.text } ?? (assistant.status.isReady || assistant.status == .checking
                                            ? "Ask \(assistant.engine.name) anything" : "Set up \(assistant.engine.name)"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)
            Text(assistant.engine.isClaude ? "Claude \(assistant.claudeModel.title)" : "Runs on this Mac")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 11, leading: 11, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { model.openAssistant() }
        .onHover { hovering = $0 }
        .help("Open the assistant")
    }
}
