import AppKit
import SwiftUI

/// Settings, inside the notch: sections down the left, the chosen one on the right.
/// Everything that used to be in the drop-down menu lives here.
struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant

    var body: some View {
        let size = model.size(model.level)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "gearshape", title: "Settings") {
                    EmptyView()
                }
            } trailing: {
                HStack(spacing: 2) {
                    if let note = model.updateNote {
                        UpdateNote(text: note)
                            .padding(.trailing, 4)
                    }
                    IconButton(symbol: "xmark", label: "Close Settings (Esc)", action: { model.goHome() })
                }
                .padding(.trailing, 4)
            }

            HStack(alignment: .top, spacing: 10) {
                SettingsSidebar(model: model, settings: settings)
                    .frame(width: 172)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        switch model.settingsSection {
                        case .general:
                            GeneralSettings(model: model)
                        case .accounts:
                            AccountSettings(model: model, settings: settings)
                        case .assistant:
                            AssistantSettings(assistant: assistant)
                        case .gmail:
                            GmailLinkSettings(settings: settings)
                        case .updates:
                            UpdateSettings(settings: settings)
                        }
                    }
                    .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(model.settingsSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            }
            .padding(.top, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear { assistant.checkSetup() }
    }
}

// MARK: Sidebar

struct SettingsSidebar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                SidebarRow(section: section,
                           selected: model.settingsSection == section,
                           flagged: flagged(section),
                           choose: { model.settingsSection = section })
            }
            Spacer(minLength: 8)
            QuitRow(action: { settings.quit() })
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A dot beside a section that needs a look: an update to install, or a Gmail link that stopped.
    private func flagged(_ section: SettingsSection) -> Bool {
        switch section {
        case .updates:
            if case .available = settings.update { return true }
            return false
        case .gmail:
            return settings.link.lastSync != nil && !settings.link.isHealthy
        default:
            return false
        }
    }
}

struct SidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let flagged: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if flagged {
                    Circle()
                        .fill(Theme.text)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.raised : (hovering ? Theme.surface : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct QuitRow: View {
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text("Quit Notch Inbox")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Theme.text : Theme.tertiary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.surface : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: General

struct GeneralSettings: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        SettingsHeading(title: "Show Notch Inbox as")
        HStack(spacing: 10) {
            ModeCard(symbol: "menubar.rectangle", title: "Notch at the top",
                     detail: "Opens when you hover over the notch. Unread counts sit beside the camera.",
                     selected: !model.minimised, choose: { model.setMinimised(false) })
            ModeCard(symbol: "envelope", title: "Mail tab",
                     detail: "A small tab you can slide along the top of the screen. Click it to open.",
                     selected: model.minimised, choose: { model.setMinimised(true) })
        }

        SettingsDivider()
        SettingsRow(title: "Panel sizes",
                    detail: "Drag the bottom edge or corner of an open panel to resize it. Double-click the corner for its standard size.") {
            PillButton(title: "Reset All Sizes", action: { model.resetAllSizes() })
        }
        SettingsDivider()
        SettingsRow(title: "Keyboard",
                    detail: "Esc goes back a step. In Mail, 1, 2 and 3 open your inboxes and O opens the email in Gmail.") {
            EmptyView()
        }
    }
}

/// One of the two ways to show the app, as a card you click.
struct ModeCard: View {
    let symbol: String
    let title: String
    let detail: String
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.tertiary)
                }
                .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.raised : Theme.lane))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.22 : (hovering ? 0.12 : 0.05)), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Mail accounts

struct AccountSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Mail accounts",
                        detail: "The notch shows up to three accounts. Primary shows Gmail's Primary tab plus Classroom and other mail from Google; Whole inbox shows every tab.")
        if settings.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Gmail accounts linked yet.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                PillButton(title: "Set Up the Gmail Link", prominent: true, action: { model.settingsSection = .gmail })
            }
        } else {
            VStack(spacing: 8) {
                ForEach(settings.accounts) { account in
                    AccountSettingRow(account: account, settings: settings)
                }
            }
        }
    }
}

struct AccountSettingRow: View {
    let account: AppSettings.Account
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(account.hidden ? Theme.tertiary.opacity(0.5) : (account.colorHex.map { Color(hex: $0) } ?? Theme.tertiary))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.id)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(account.hidden ? Theme.tertiary : Theme.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ChoiceSegments(options: [
                ChoiceSegments<InboxChoice>.Option(value: .primary, title: "Primary",
                                      help: "Gmail's Primary tab, plus Classroom and other mail from Google"),
                ChoiceSegments<InboxChoice>.Option(value: .everything, title: "Whole inbox",
                                      help: "Every tab: Primary, Promotions, Social and Updates"),
            ], selected: account.inbox, choose: { settings.chooseInbox($0, for: account.id) })
            .opacity(account.hidden ? 0.5 : 1)
            Toggle("", isOn: Binding(get: { !account.hidden }, set: { settings.setHidden(!$0, for: account.id) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(account.hidden ? "Show in the notch" : "Hide from the notch")
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lane))
    }

    private var status: String {
        if account.hidden { return "Hidden from the notch" }
        if !account.inNotch { return "No room: hide another account to show this one" }
        return "\(UnreadText.format(account.unread)) unread · in the notch"
    }
}

// MARK: Assistant

struct AssistantSettings: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        SettingsHeading(title: "Who answers")
        VStack(spacing: 6) {
            ForEach(AssistantEngine.allCases, id: \.self) { engine in
                EngineRow(engine: engine, selected: assistant.engine == engine, choose: { assistant.engine = engine })
            }
        }

        if assistant.engine.isClaude {
            SettingsRow(title: "Model", detail: modelDetail) {
                ChoiceSegments(options: ClaudeModel.allCases.map {
                    ChoiceSegments<ClaudeModel>.Option(value: $0, title: $0.title, help: $0.note)
                }, selected: assistant.claudeModel, choose: { assistant.claudeModel = $0 })
            }
        }

        SettingsDivider()
        switch assistant.engine {
        case .claudeCode:
            ClaudeCodeStatus(assistant: assistant)
        case .claudeAPI:
            APIKeyEditor(assistant: assistant)
        case .qwen:
            QwenStatus(assistant: assistant)
        }

        SettingsDivider()
        SettingsToggle(title: "Share my newest emails and notes",
                       detail: assistant.engine.isClaude
                           ? "Senders, subjects and times of your 20 newest emails, and your latest notes, are sent to Anthropic with each question. Off keeps them on this Mac."
                           : "Qwen sees senders, subjects and times of your newest emails, and your latest notes. They stay on this Mac.",
                       isOn: $assistant.sharesContext)
    }

    private var modelDetail: String {
        switch assistant.claudeModel {
        case .haiku: return "Haiku answers fastest; good for quick questions."
        case .sonnet: return "Sonnet is quick and capable: the best fit for most things."
        case .opus: return "Opus thinks hardest, but is slower and uses more of your plan."
        }
    }
}

/// One way for the assistant to answer, as a row you click.
struct EngineRow: View {
    let engine: AssistantEngine
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                Image(systemName: engine.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(selected ? Theme.hover : Theme.raised))
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(engine.caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Theme.text : Theme.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.raised : Theme.lane))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.22 : (hovering ? 0.12 : 0.05)), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ClaudeCodeStatus: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        switch assistant.status {
        case .checking:
            StatusLine(state: .waiting, text: "Looking for Claude Code on this Mac…")
        case .noClaudeCode:
            VStack(alignment: .leading, spacing: 8) {
                StatusLine(state: .problem, text: "Claude Code isn't installed on this Mac")
                SettingsDetail(text: "Install it in Terminal with this command, then type claude, press Return and sign in to your Claude account.")
                CommandBox(command: ClaudeSetup.installCommand)
                PillButton(title: "Check Again", prominent: true, action: { assistant.checkSetup() })
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                StatusLine(state: .good, text: "Using Claude Code at \(shortPath)")
                SettingsDetail(text: "If Claude says it isn't signed in, open Terminal, type claude, press Return and sign in.")
            }
        }
    }

    private var shortPath: String {
        let path = assistant.claudePath ?? "claude"
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }
}

struct APIKeyEditor: View {
    @ObservedObject var assistant: Assistant
    @State var typed = ""
    @State var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = assistant.apiKeyHint {
                HStack(spacing: 8) {
                    StatusLine(state: .good, text: "API key saved: \(hint)")
                    Spacer(minLength: 8)
                    PillButton(title: "Remove", action: { assistant.removeAPIKey() })
                }
            } else {
                StatusLine(state: .problem, text: "No API key yet")
            }
            HStack(spacing: 8) {
                SecureField(assistant.apiKeyHint == nil ? "Paste your API key (sk-ant-…)" : "Paste a new key to replace it", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                    .onSubmit(save)
                PillButton(title: "Save", prominent: true, action: save)
            }
            if let problem = problem {
                Text(problem)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.text2)
            }
            SettingsDetail(text: "Make a key at console.anthropic.com → API Keys. You pay Anthropic per question. The key stays on this Mac, in a file only your account can read.")
        }
    }

    private func save() {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if assistant.saveAPIKey(typed) {
            typed = ""
            problem = nil
        } else {
            problem = "That doesn't look like an API key. Copy it again from the console."
        }
    }
}

struct QwenStatus: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        switch assistant.status {
        case .checking:
            StatusLine(state: .waiting, text: "Looking for Qwen on this Mac…")
        case .noOllama, .noModel:
            VStack(alignment: .leading, spacing: 8) {
                StatusLine(state: .problem, text: assistant.status == .noOllama ? "Ollama isn't running" : "No Qwen model downloaded yet")
                SettingsDetail(text: assistant.status == .noOllama
                               ? "Install Ollama from ollama.com and open it. Then download Qwen in Terminal (several GB, so use Wi-Fi):"
                               : "Download the Qwen model that suits this Mac in Terminal (several GB, so use Wi-Fi):")
                CommandBox(command: "ollama pull \(assistant.suggestedModel)")
                PillButton(title: "Check Again", prominent: true, action: { assistant.checkSetup() })
            }
        default:
            StatusLine(state: .good, text: "Using \(assistant.modelName) with Ollama, on this Mac")
        }
    }
}

// MARK: Gmail link

struct GmailLinkSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let link = settings.link

        SettingsHeading(title: "Gmail link",
                        detail: "A small add-on in Chrome passes the mail of every Gmail account signed in there to this app. It only talks to Gmail and to this app, on this Mac.")
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            StatusLine(state: link.lastSync == nil ? .problem : (link.isHealthy ? .good : .waiting),
                       text: link.summary(now: context.date))
        }
        VStack(alignment: .leading, spacing: 3) {
            SettingsDetail(text: "Add-on running in Chrome: \(link.addOnRunning ?? "not heard from yet")")
            SettingsDetail(text: "Add-on this app installs: \(link.addOnInstalled ?? "not installed yet")")
        }
        HStack(spacing: 8) {
            PillButton(title: "Set Up Browser Link…", prominent: link.lastSync == nil, action: { settings.setUpBrowserLink() })
            PillButton(title: "Show Add-on Folder", action: { settings.showAddOnFolder() })
            PillButton(title: "Copy Debug Info", action: { settings.copyDebugInfo() })
        }
        SettingsDetail(text: "Copy Debug Info copies counts and addresses only, never what your emails say.")
    }
}

// MARK: Updates

struct UpdateSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Updates",
                        detail: "Notch Inbox looks for a new build every 2 minutes. It only installs one when you click Install.")
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.build > 0 ? "Build \(settings.build)" : "Local build")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                if let checked = settings.lastUpdateCheck {
                    TimelineView(.periodic(from: Date(), by: 30)) { _ in
                        Text("Last checked \(MailTime.label(for: checked))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            switch settings.update {
            case .available(let build, _):
                PillButton(title: "Install Build \(build)", prominent: true, action: { settings.installUpdate() })
            case .checking, .installing, .unavailable:
                EmptyView()
            default:
                PillButton(title: "Check for Updates", action: { settings.checkForUpdates() })
            }
        }
        if case .available(_, let notes) = settings.update, !notes.isEmpty {
            Text(notes)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.body)
                .lineLimit(10)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
        }
    }

    private var statusText: String {
        switch settings.update {
        case .idle: return "Not checked yet"
        case .checking: return "Checking for updates…"
        case .upToDate: return "Up to date"
        case .available(let build, _): return "Build \(build) is ready to install"
        case .installing: return "Installing… Notch Inbox restarts by itself"
        case .failed(let message): return "Couldn't check: \(message)"
        case .unavailable: return "Updates work in the installed app"
        }
    }
}

// MARK: Pieces

struct SettingsHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let detail = detail {
                SettingsDetail(text: detail)
            }
        }
    }
}

struct SettingsDetail: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

/// A setting with its title and explanation on the left and its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                SettingsDetail(text: detail)
            }
            control()
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// A green, amber or red dot with a line of status.
struct StatusLine: View {
    enum Tone {
        case good
        case waiting
        case problem
    }

    let state: Tone
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var color: Color {
        switch state {
        case .good: return Color(hex: 0x34C759)
        case .waiting: return Color(hex: 0xFFB340)
        case .problem: return Color(hex: 0xFF5F57)
        }
    }
}

/// Two or three choices side by side in a capsule, like a segmented control.
struct ChoiceSegments<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let help: String
    }

    let options: [Option]
    let selected: Value
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selected
                Button(action: { choose(option.value) }) {
                    Text(option.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(isSelected ? Theme.text : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.help)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.raised))
        .fixedSize()
    }
}
