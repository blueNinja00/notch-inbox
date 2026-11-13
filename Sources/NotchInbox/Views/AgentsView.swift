import AppKit
import SwiftUI

/// The agent room: your groups of tasks down the side (with the team chat, the library and
/// your recipes under them), and beside them the tasks of the group you pick, as a table
/// that shows how each is going. Click a task for its own page: what it's doing, what it
/// did, and its report. The box along the bottom adds a task to the group.
struct AgentsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AgentsStore
    @ObservedObject var assistant: Assistant
    @ObservedObject var settings: AppSettings
    let expanded: Bool

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)
        let team = store.team
        let open = team.job(model.agentOpen)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: HomeTile.agents.symbol, title: "Agents") {
                    if let busy = team.busyLine {
                        AgentsBusyTag(text: busy)
                    }
                    AgentsUsageTag(usage: assistant.usage, cap: settings.agentDailyCap, open: { model.openSettings(.assistant) })
                }
            } trailing: {
                HStack(spacing: 2) {
                    IconButton(symbol: "sparkles", label: "Ask the assistant to hand out jobs", action: { model.openAssistant() })
                    IconButton(symbol: "keyboard", label: "Shortcuts for this room, and changing their keys",
                               action: { model.openSettings(.shortcuts) })
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make smaller" : "Expand",
                               action: { expanded ? model.back() : model.expandAgents() })
                    SettingsButton(model: model, section: .assistant)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                AgentSidebar(model: model, team: team, keys: settings.keybinds)
                    .frame(width: expanded ? 224 : 200)
                Group {
                    if model.agentsPage == .teamChat, let room = model.teamStore {
                        TeamChatView(model: model, store: room, on: settings.agentsTeamChat)
                    } else if model.agentsPage == .library, let reports = model.reportsStore {
                        ReportLibraryView(model: model, store: reports)
                    } else if model.agentsPage == .recipes, let recipes = model.recipesStore {
                        RecipesView(model: model, store: recipes, assistant: assistant)
                    } else if model.agentShowsWork, let job = open {
                        AgentDetail(model: model, job: job, floor: team.floor(of: job.id), team: team)
                            .id(job.id)
                    } else if team.jobs.isEmpty && team.groups.isEmpty {
                        AgentsWelcome(model: model, assistant: assistant, settings: settings,
                                      recipes: model.recipesStore?.book.ordered ?? [])
                    } else {
                        AgentGroupView(model: model, team: team, group: team.group(model.agentGroupOpen)?.id, keys: settings.keybinds)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            }
            .padding(.top, 6)

            AgentJobField(model: model, assistant: assistant, group: team.groupName(model.agentGroupOpen), keys: settings.keybinds)
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear { assistant.checkSetup() }
    }
}

/// How agents look: a colour and a symbol for how each one is going.
enum AgentLook {
    static func tint(_ status: AgentJob.Status) -> Color {
        switch status {
        case .idle: return Theme.tertiary
        case .queued: return Theme.tertiary
        case .working: return Theme.accent
        case .done: return Theme.good
        case .failed: return Theme.danger
        case .stopped: return Theme.warning
        }
    }

    static func symbol(_ status: AgentJob.Status) -> String {
        switch status {
        case .idle: return "circle"
        case .queued: return "clock.fill"
        case .working: return "circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        }
    }

    /// A state's words in the table: quiet until it's started, then its own colour.
    static func ink(_ status: AgentJob.Status) -> Color {
        switch status {
        case .idle: return Theme.tertiary
        case .queued: return Theme.secondary
        case .working: return Theme.text
        case .done: return Theme.good
        case .failed: return Theme.danger
        case .stopped: return Theme.warning
        }
    }

    /// A state's stretch of a status bar. What hasn't been started has none.
    static func bar(_ status: AgentJob.Status) -> Color {
        switch status {
        case .idle: return Color.clear
        case .queued: return Theme.accent.opacity(0.3)
        case .working: return Theme.accent
        case .done: return Theme.good
        case .failed: return Theme.danger
        case .stopped: return Theme.warning
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }()

    /// "3:42 pm", for a step in the log.
    static func time(_ date: Date) -> String {
        clock.string(from: date)
    }
}

/// "2 working · 1 waiting", beside the room's name.
struct AgentsBusyTag: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            AgentPulse()
            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.leading, 2)
    }
}

/// What the notch has used today, beside the room's name. It turns amber once the day's
/// cap is reached and new agents are being held. Click for the full count in Settings.
struct AgentsUsageTag: View {
    @ObservedObject var usage: UsageStore
    let cap: Int
    let open: () -> Void

    var body: some View {
        let today = usage.log.today()
        let over = usage.log.isOver(cap: cap)

        if today.runs > 0 || cap > 0 {
            Button(action: open) {
                Text(UsageText.todayTag(today, cap: cap))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(over ? Theme.warning : Theme.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .overlay(Capsule().strokeBorder(over ? Theme.warning.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
            .help(over ? "Today's usage cap is reached, so new agents are held until tomorrow. Click to change it."
                       : "Tokens the notch has used today: \(UsageText.line(today)). Click for more.")
        }
    }
}

/// A dot that breathes while an agent works.
struct AgentPulse: View {
    var size: CGFloat = 6
    @State var dim = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .opacity(dim ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// A small heading inside the room: "THE JOB", "WHAT IT DID".
struct AgentCaption: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
    }
}

/// An agent's floor number. Filled in the accent colour while it works; a small mark at
/// the corner says how it ended.
struct AgentFloorBadge: View {
    let floor: Int
    let status: AgentJob.Status
    var size: CGFloat = 28

    var body: some View {
        Text("\(floor)")
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(status == .working ? Theme.onAccent : Theme.text2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(status == .working ? Theme.accent : Theme.avatar))
            .overlay(alignment: .bottomTrailing) {
                if status != .working {
                    Image(systemName: AgentLook.symbol(status))
                        .font(.system(size: size * 0.36, weight: .bold))
                        .foregroundStyle(AgentLook.tint(status))
                        .background(Circle().fill(Color.black).padding(1))
                        .offset(x: 4, y: 4)
                }
            }
            .help("Task \(floor): \(AgentFloorBadge.word(status))")
    }

    static func word(_ status: AgentJob.Status) -> String {
        switch status {
        case .idle: return "ready to start"
        case .queued: return "waiting its turn"
        case .working: return "working"
        case .done: return "done"
        case .failed: return "couldn't finish"
        case .stopped: return "stopped"
        }
    }
}

/// How long an agent has been working (ticking), or took.
struct AgentClock: View {
    let job: AgentJob

    var body: some View {
        if job.status == .working {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                Text(job.clock(now: context.date))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
        } else if job.started != nil {
            Text(job.clock(now: Date()))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// An agent's right-click menu.
struct AgentMenu: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    let team: AgentTeam
    /// A chain still going is built on its work, so it can't be taken out yet.
    var held = false
    /// It's a stage of a chain that stopped short, and the next agent could start from it.
    var canCarryOn = false

    var body: some View {
        let own = team.group(job.group)?.id
        let others = team.groupIDs.filter { $0 != own }

        Button("Open") { model.showAgent(job.id) }
        if job.isIdle {
            Button("Start") { model.startTask(job.id) }
        } else if job.isActive {
            Button("Stop") { model.stopAgent(job.id) }
        } else {
            Button("Run Again") { model.agentAgain(job.id) }
        }
        if Recipe.canSave(job) {
            Button("Duplicate") { model.duplicateAgent(job.id) }
        }
        if !others.isEmpty {
            Menu("Move to Group") {
                ForEach(others, id: \.self) { id in
                    Button(team.groupName(id)) { model.moveAgent(job.id, to: id) }
                }
            }
        }
        if canCarryOn {
            Button("Carry On the Chain from Here") { model.carryOnChain(job.id) }
        }
        if !job.folder.isEmpty {
            Button("Show Its Folder") { model.onShowAgentFolder?(job.id) }
        }
        if Recipe.canSave(job) {
            Button("Save Its Job as a Recipe") { model.saveRecipe(from: job.id) }
        }
        if !job.isActive && !held {
            Divider()
            Button(job.isIdle ? "Remove This Task" : "Remove from the Room") { model.removeAgent(job.id) }
        }
    }
}

// MARK: The team chat

/// The team chat: what agents, the chief of staff and you have said, newest at the bottom.
struct TeamChatView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TeamStore
    let on: Bool

    var body: some View {
        let messages = store.room.messages

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Team chat")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 4)
                if !messages.isEmpty {
                    SmallPill(title: "Clear", symbol: "xmark", action: { model.onClearTeamChat?() })
                        .help("Empty the team chat")
                }
            }
            if messages.isEmpty {
                Text(on ? "Working agents post what they find and what they need here, and read each other's posts so they don't double up. Type below to say something to everyone: the chief of staff answers you, and every working agent can read it."
                        : "The team chat is switched off in Settings → Assistant, so agents work without it.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { scroller in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { message in
                                TeamBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: messages.last?.id) { last in
                        if let last = last {
                            scroller.scrollTo(last, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        guard let last = messages.last?.id else { return }
                        DispatchQueue.main.async {
                            scroller.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One message in the team chat, with who said it.
struct TeamBubble: View {
    let message: TeamMessage

    var body: some View {
        let mine = message.from == .you

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(TeamBubble.who(message))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(message.from == .chief ? Theme.accent : Theme.text2)
                Text(AgentLook.time(message.at))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
            if mine {
                // Your own words are shown as you typed them.
                Text(message.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(2.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MarkdownBlocks(text: message.text, fills: false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(mine ? Theme.raised : Theme.lane))
    }

    static func who(_ message: TeamMessage) -> String {
        if case .agent(let name, let floor) = message.from {
            return "\(name) · task \(floor)"
        }
        return message.name
    }
}

// MARK: One agent

/// The agent you picked: its job, what it's doing, what it saved and its report.
struct AgentDetail: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    let floor: Int
    let team: AgentTeam

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentHeader(model: model, job: job, floor: floor, held: team.heldForChains.contains(job.id))
            if job.chain != nil {
                AgentChainStrip(model: model, steps: team.chainSteps(of: job))
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if job.isIdle {
                        AgentTaskEditor(model: model, id: job.id)
                    } else {
                        AgentTask(task: job.task)
                    }
                    if let problem = job.problem, !problem.isEmpty {
                        AgentProblem(text: problem, failed: job.status == .failed)
                    }
                    if team.canCarryOn(job.id) {
                        AgentCarryOn(next: job.chain?.next(after: job.id)?.role ?? "next agent", carryOn: { model.carryOnChain(job.id) })
                    }
                    if !job.files.isEmpty {
                        AgentFileChips(model: model, job: job)
                    }
                    if job.status == .working {
                        // While it works, what it's doing comes first.
                        AgentLog(steps: job.steps)
                        AgentReportText(report: job.report, finished: false)
                    } else {
                        AgentReportText(report: job.report, finished: true)
                        AgentLog(steps: job.steps)
                    }
                    if job.isIdle {
                        Text("It hasn't been started. Change the job above if you like, then press Start here, or Start All on its group.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                    if job.isActive && job.steps.isEmpty && job.report.isEmpty {
                        Text(job.status == .queued ? "It starts as soon as another agent finishes." : "Getting started…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
    }
}

struct AgentHeader: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    let floor: Int
    var held = false

    var body: some View {
        HStack(spacing: 9) {
            IconButton(symbol: "chevron.left", label: "Back to its group (Esc)", size: 26, action: { model.closeAgent() })
            AgentFloorBadge(floor: floor, status: job.status, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Text(job.statusLine(now: context.date))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            AgentActions(model: model, job: job, held: held)
        }
    }
}

/// Where an agent stands in its chain: every stage in order. Click another stage to see
/// the agent that did it.
struct AgentChainStrip: View {
    @ObservedObject var model: NotchModel
    let steps: [AgentChainStep]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(steps) { step in
                AgentChainPill(step: step, open: { open(step) })
            }
            Spacer(minLength: 0)
        }
    }

    private func open(_ step: AgentChainStep) {
        if let job = step.job, step.opens {
            model.showAgent(job.id)
        }
    }
}

/// One stage in the strip: how it went, and whose it is.
struct AgentChainPill: View {
    let step: AgentChainStep
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            if step.index > 0 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 5) {
                Image(systemName: AgentChainPill.symbol(for: step))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AgentChainPill.tint(for: step))
                Text(step.role)
                    .font(.system(size: 11.5, weight: step.isCurrent ? .semibold : .medium))
                    .foregroundStyle(AgentChainPill.ink(for: step))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .onTapGesture(perform: open)
            .onHover { hovering = $0 }
            .help(step.help)
            .accessibilityLabel(Text(step.help))
        }
    }

    private var fill: Color {
        if step.isCurrent {
            return Theme.raised
        }
        return hovering && step.opens ? Theme.hover : Theme.lane
    }

    static func symbol(for step: AgentChainStep) -> String {
        guard let job = step.job else { return step.symbol }
        return AgentLook.symbol(job.status)
    }

    static func tint(for step: AgentChainStep) -> Color {
        guard let job = step.job else { return Theme.tertiary }
        return AgentLook.tint(job.status)
    }

    static func ink(for step: AgentChainStep) -> Color {
        if step.isCurrent {
            return Theme.text
        }
        return step.job == nil ? Theme.tertiary : Theme.secondary
    }
}

/// Under a stage of a chain that stopped short: the next agent can start from what it left.
struct AgentCarryOn: View {
    let next: String
    let carryOn: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("The chain stopped here. The \(next.lowercased()) can start from what this one left, or run this stage again.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            SmallPill(title: "Carry On", symbol: "arrow.right", action: carryOn)
                .help("Start the \(next.lowercased()) on what this agent had written and saved")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
    }
}

/// Stop it while it works; afterwards copy its report, run it again, or take it out.
struct AgentActions: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    /// A chain still going is built on its work, so it can't be taken out yet.
    var held = false
    @State var copied = false

    var body: some View {
        HStack(spacing: 6) {
            if job.isIdle {
                SmallPill(title: "Start", symbol: "play.fill", action: { model.startTask(job.id) })
                    .help("Start this task")
            } else if job.isActive {
                SmallPill(title: "Stop", symbol: "stop.fill", action: { model.stopAgent(job.id) })
                    .help("Stop this agent. What it has written so far is kept.")
            } else {
                if !job.report.isEmpty {
                    SmallPill(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", action: copy)
                        .help("Copy the report")
                }
                SmallPill(title: "Again", symbol: "arrow.clockwise", action: { model.agentAgain(job.id) })
                    .help(job.chain == nil ? "Give the same job to a new agent" : "Do this stage again with a new agent. The chain carries on from it.")
            }
            if !job.folder.isEmpty {
                IconButton(symbol: "folder", label: "Open this agent's folder in Finder", size: 26,
                           action: { model.onShowAgentFolder?(job.id) })
            }
            if Recipe.canSave(job) {
                IconButton(symbol: "text.book.closed", label: "Save this job as a recipe, to run again", size: 26,
                           action: { model.saveRecipe(from: job.id) })
            }
            if !job.isActive && !held {
                IconButton(symbol: "trash", label: AgentRowActions.removeLabel(job), size: 26,
                           action: { model.removeAgent(job.id) })
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(job.report, forType: .string)
        copied = true
    }
}

/// What the agent was told to do. Click for all of it.
struct AgentTask: View {
    let task: String
    @State var whole = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            AgentCaption(text: "The job")
            Text(task)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .lineLimit(whole ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { whole.toggle() }
        .help(whole ? "Click to show less" : "Click to show the whole job")
    }
}

/// A task that hasn't started: what it will be asked to do can still be changed. It's
/// saved as it's typed.
struct AgentTaskEditor: View {
    @ObservedObject var model: NotchModel
    let id: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            AgentCaption(text: "The job (yours to change until it's started)")
            TextField("What to find out, write or compare", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .lineLimit(2...10)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
        }
    }

    /// The job, read from the room as it's typed.
    private var text: Binding<String> {
        Binding(
            get: { model.agentsStore?.team.job(id)?.task ?? "" },
            set: { typed in model.rewriteTask(id, to: typed) }
        )
    }
}

struct AgentProblem: View {
    let text: String
    let failed: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .foregroundStyle(failed ? Theme.danger : Theme.warning)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The files an agent saved, to open with a click.
struct AgentFileChips: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AgentCaption(text: job.files.count == 1 ? "File it saved" : "Files it saved")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(job.files.suffix(12), id: \.self) { file in
                        SmallPill(title: AgentFiles.shortName(file), symbol: AgentFiles.symbol(for: file),
                                  action: { model.onOpenAgentFile?(job.id, file) })
                            .help(AgentFiles.opensDirectly(file) ? "Open \(file)" : "Show \(file) in Finder")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// What the agent did, newest first.
struct AgentLog: View {
    let steps: [AgentStep]
    /// The most steps drawn.
    static let most = 40

    var body: some View {
        if !steps.isEmpty {
            let shown = Array(steps.suffix(AgentLog.most).reversed())
            VStack(alignment: .leading, spacing: 5) {
                AgentCaption(text: "What it did, newest first")
                ForEach(shown) { step in
                    AgentStepRow(step: step)
                }
                if steps.count > AgentLog.most {
                    Text("and \(steps.count - AgentLog.most) earlier steps")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.leading, 21)
                }
            }
        }
    }
}

struct AgentStepRow: View {
    let step: AgentStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: step.symbol)
                .font(.system(size: step.kind == .note ? 5 : 10, weight: .semibold))
                .foregroundStyle(step.kind == .problem ? Theme.warning : Theme.tertiary)
                .frame(width: 14)
            Text(step.text)
                .font(.system(size: 12))
                .foregroundStyle(step.kind == .problem ? Theme.warning : Theme.body)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(AgentLook.time(step.at))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}

// MARK: The report

/// An agent's report, drawn from its Markdown: headings, bullets, tables and all.
struct AgentReportText: View {
    let report: String
    let finished: Bool

    var body: some View {
        if !report.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                AgentCaption(text: finished ? "Its report" : "What it's writing")
                MarkdownBlocks(text: report, lazily: true)
                if AgentReport.isCut(report) {
                    Text("There's more: Copy has the whole report.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

// MARK: A new job

/// When no agent is picked: what the room is for, what agents can do, and jobs to try.
struct AgentsWelcome: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant
    @ObservedObject var settings: AppSettings
    /// Your recipes, the ones you ran last first.
    var recipes: [Recipe] = []

    var body: some View {
        let tools = assistant.engine == .claudeCode
        let needsSetup = !assistant.status.isReady && assistant.status != .checking

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 9) {
                Text("The agent room")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Type a task in the box below and press Return: it joins the group that's showing, ready to start. Press Start on it, or Start All on its group, and an agent works on it by itself while you get on with something else. The table shows how each one is going; click a task to watch it and read its report. Make groups with the + beside Groups. Or just ask the assistant, and it hands the big jobs out for you.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AgentBrief.powers(tools: tools, web: tools && settings.agentsUseWeb, engine: assistant.engine.title,
                                       claude: assistant.engine.isClaude))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Switch on Chain beside the box for work that has to be right. " + AgentChain.about)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if needsSetup {
                    PillButton(title: "Set Up \(assistant.engine.name) First", prominent: true, action: { model.openAssistant() })
                } else if recipes.isEmpty {
                    AgentCaption(text: "Jobs to start from")
                        .padding(.top, 2)
                    HStack(spacing: 6) {
                        ForEach(AgentBrief.examples) { example in
                            SmallPill(title: example.title, symbol: example.symbol, action: { model.agentDraft = example.job })
                                .help(example.job)
                        }
                    }
                } else {
                    AgentCaption(text: "Recipes to start from")
                        .padding(.top, 2)
                    AgentsWelcomeRecipes(model: model, recipes: recipes)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
    }
}

/// On the welcome: your first few recipes, each one click from being filled in and run.
struct AgentsWelcomeRecipes: View {
    @ObservedObject var model: NotchModel
    let recipes: [Recipe]
    /// How many are offered here; the Recipes page has them all.
    static let most = 5

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(recipes.prefix(AgentsWelcomeRecipes.most)) { recipe in
                    SmallPill(title: recipe.title, symbol: recipe.chain ? "link" : "text.book.closed",
                              action: { model.showRecipe(recipe.id) })
                        .help(recipe.line)
                }
                if recipes.count > AgentsWelcomeRecipes.most {
                    SmallPill(title: "All \(recipes.count)", symbol: "ellipsis", action: { model.openRecipes() })
                        .help("See all your recipes")
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// The box along the bottom of the room: type a task and press Return, and it joins the
/// group that's showing, ready to start. (While the team chat is showing, it posts there.)
struct AgentJobField: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant
    /// The group a new task goes in, by name.
    let group: String
    /// Your shortcuts, for the tooltips.
    let keys: Keybinds
    @FocusState private var typing: Bool

    init(model: NotchModel, assistant: Assistant, group: String, keys: Keybinds) {
        self.model = model
        self.assistant = assistant
        self.group = group
        self.keys = keys
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(AgentJobField.prompt(teamChat: model.teamChatOpen, chain: model.agentDraftChain, group: group), text: $model.agentDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1...4)
                .focused($typing)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            if !model.teamChatOpen {
                if model.recipesStore != nil {
                    IconButton(symbol: "text.book.closed", label: AgentJobField.bookLabel(model.agentDraft), size: 32, action: keep)
                }
                ChainToggle(on: $model.agentDraftChain, hint: keys.hint(for: .chain))
            }
            IconButton(symbol: model.teamChatOpen ? "arrow.up" : "plus",
                       label: AgentJobField.sendLabel(teamChat: model.teamChatOpen, chain: model.agentDraftChain, group: group), size: 32,
                       tint: Theme.text, action: send)
        }
        .onAppear { typing = true }
        // A shortcut (New task) or a button asked for the cursor.
        .onChange(of: model.agentsFocusTick) { _ in
            if model.takeFocus(.box) {
                typing = true
            }
        }
    }

    /// Whether there's enough typed to be worth keeping as a recipe.
    static func canKeep(_ draft: String) -> Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    /// The book beside the box: it keeps what's typed as a recipe, or with nothing typed
    /// it opens the recipes you have.
    static func bookLabel(_ draft: String) -> String {
        canKeep(draft) ? "Save this job as a recipe, to run again (it isn't added)" : "Your recipes: jobs saved to run again"
    }

    private func keep() {
        if AgentJobField.canKeep(model.agentDraft) {
            model.saveDraftAsRecipe()
        } else {
            model.openRecipes()
        }
    }

    static func prompt(teamChat: Bool, chain: Bool, group: String) -> String {
        if teamChat {
            return "Say something to the team: the chief and every working agent can read it…"
        }
        return chain ? "Add a chain to \(group): it's researched, written, then checked. It waits until you press Start…"
                     : "Add a task to \(group): what to find out, write or compare. It waits until you press Start…"
    }

    static func sendLabel(teamChat: Bool, chain: Bool, group: String) -> String {
        if teamChat {
            return "Post it (Return)"
        }
        return chain ? "Add it to \(group) as a chain (Return). It waits there until you press Start."
                     : "Add it to \(group) (Return). It waits there until you press Start."
    }

    private func send() {
        // Nothing can answer in the team chat yet: the assistant's page says what to set up.
        // (A task can be added before then: it's Start that needs the assistant.)
        if model.teamChatOpen && !assistant.status.isReady && assistant.status != .checking {
            model.openAssistant()
            return
        }
        model.sendAgentDraft()
        typing = true
    }
}

/// Beside the job box: sends the job to a chain of three agents (a researcher, a writer,
/// then a checker) in place of one. It switches itself off again after each chain.
struct ChainToggle: View {
    @Binding var on: Bool
    /// Its shortcut, for the tooltip: " (⌘K)".
    var hint = ""
    @State var hovering = false

    var body: some View {
        Button(action: { on.toggle() }) {
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                Text("Chain")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Theme.onAccent : Theme.secondary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help((on ? "On: this job goes to a chain. " + AgentChain.about : AgentChain.about) + hint)
        .accessibilityLabel(Text(on ? "Chain, on" : "Chain, off"))
    }

    private var fill: Color {
        if on {
            return Theme.accent
        }
        return hovering ? Theme.hover : Theme.surface
    }
}

// MARK: On the primary menu

/// The agents' tile: how many are working, and the latest one's news.
struct AgentsToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AgentsStore
    @State var hovering = false

    var body: some View {
        let team = store.team
        let working = team.working
        let latest = working.last ?? team.newestFirst.first

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ToolIcon(symbol: HomeTile.agents.symbol)
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !working.isEmpty {
                    HStack(spacing: 5) {
                        AgentPulse()
                        Text("\(working.count)")
                            .font(.system(size: 17, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.text)
                    }
                    .help(working.count == 1 ? "1 agent working" : "\(working.count) agents working")
                }
            }
            Spacer(minLength: 0)
            if let job = latest {
                HStack(spacing: 5) {
                    if job.status != .working {
                        Image(systemName: AgentLook.symbol(job.status))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AgentLook.tint(job.status))
                    }
                    Text(job.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                Text(job.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
            } else {
                Text("Hand out a job")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Text("Research, notes and drafts, done while you work")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 11, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if let job = latest {
                model.pickAgent(job.id)
            }
            model.openAgents()
        }
        .onHover { hovering = $0 }
        .help("Open the agent room")
    }
}
