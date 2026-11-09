import AppKit
import SwiftUI

/// The assistant: chat with Qwen, running on this Mac. Expand it for more room.
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
                        Text(name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                            .help("Running on this Mac with Ollama")
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
                    IconButton(symbol: "slider.horizontal.3", label: "Menu: updates, Gmail link, Quit",
                               action: { model.showAppMenu() })
                }
                .padding(.trailing, 4)
            }

            switch assistant.status {
            case .ready:
                chat
            case .checking:
                Text("Looking for Qwen on this Mac…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noOllama, .noModel:
                AssistantSetup(assistant: assistant)
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
                TextField("Ask Qwen anything…", text: $assistant.draft, axis: .vertical)
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

            Toggle(isOn: $assistant.usesContext) {
                Text("Let Qwen see my newest emails and notes (they stay on this Mac)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 6)
        .onAppear { typing = true }
    }
}

/// One message: yours on the right, Qwen's on the left.
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

    /// Bold, italics, code and links from Qwen's Markdown, keeping its line breaks.
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
            Text("Ask about your day, your email or anything else. Qwen runs on this Mac.")
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
        let pull = "ollama pull \(assistant.suggestedModel)"

        VStack(alignment: .leading, spacing: 10) {
            Text(assistant.status == .noOllama ? "Set up Qwen on this Mac" : "One more step: download Qwen")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if assistant.status == .noOllama {
                step(1, "Install Ollama from ollama.com (free), then open it.")
            }
            step(assistant.status == .noOllama ? 2 : 1,
                 "In Terminal, run this. It downloads the Qwen model that suits your Mac's memory:")
            HStack(spacing: 8) {
                Text(pull)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
                IconButton(symbol: "doc.on.doc", label: "Copy", size: 28, action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pull, forType: .string)
                })
            }
            step(assistant.status == .noOllama ? 3 : 2, "When it's finished, click Check Again.")
            Button(action: { assistant.checkSetup() }) {
                Text("Check Again")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.text))
            }
            .buttonStyle(.plain)
            Text("Everything stays on your Mac: Qwen runs locally, and nothing you ask is sent anywhere.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 10)
        .padding(.leading, 6)
    }

    private func step(_ number: Int, _ text: String) -> some View {
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
            Text(last.map { $0.text } ?? (assistant.status == .noOllama || assistant.status == .noModel ? "Set up Qwen" : "Ask Qwen anything"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)
            Text("Runs on this Mac")
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
