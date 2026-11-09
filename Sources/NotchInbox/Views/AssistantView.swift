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
                            ChatBubble(message: message, thinking: assistant.isAnswering && message.id == assistant.messages.last?.id)
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
        }
        .padding(.top, 6)
        .onAppear { typing = true }
    }
}

/// One message: yours on the right, the assistant's on the left.
struct ChatBubble: View {
    let message: Assistant.Message
    let thinking: Bool

    var body: some View {
        let mine = message.role == .user
        let text = message.text

        HStack {
            if mine { Spacer(minLength: 60) }
            Group {
                if text.isEmpty && thinking {
                    Text("Thinking…")
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text(ChatBubble.formatted(text))
                        .foregroundStyle(message.failed ? Theme.tertiary : (mine ? Theme.text : Theme.body))
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 13))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(mine ? Theme.raised : Theme.surface))
            if !mine { Spacer(minLength: 60) }
        }
    }

    /// Bold, italics, code and links from the answer's Markdown, keeping its line breaks.
    static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Ideas to start with when the chat is empty.
struct Suggestions: View {
    @ObservedObject var assistant: Assistant

    private let ideas = [
        "Summarise my unread emails",
        "What's due soon?",
        "Plan the rest of my day",
        "Help me write a reply",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(assistant.engine.isClaude
                 ? "Ask about your day, your email or anything else."
                 : "Ask about your day, your email or anything else. Qwen runs on this Mac.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.tertiary)
            HStack(spacing: 6) {
                ForEach(ideas, id: \.self) { idea in
                    Button(action: { assistant.send(idea) }) {
                        Text(idea)
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
                .background(Capsule().fill(prominent ? Theme.text.opacity(hovering ? 1 : 0.92) : (hovering ? Theme.hover : Theme.raised)))
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
