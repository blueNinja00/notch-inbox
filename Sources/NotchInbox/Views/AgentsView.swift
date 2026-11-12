import AppKit
import SwiftUI

/// The agent room: every agent you've handed a job to, newest on top like the floors of a
/// tower, and the one you pick beside it: what it's doing, what it did, and its report.
/// The box along the bottom hands out a new job.
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
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make smaller" : "Expand",
                               action: { expanded ? model.back() : model.expandAgents() })
                    SettingsButton(model: model, section: .assistant)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                AgentTower(model: model, team: team)
                    .frame(width: expanded ? 320 : 290)
                Group {
                    if model.teamChatOpen, let room = model.teamStore {
                        TeamChatView(model: model, store: room, on: settings.agentsTeamChat)
                    } else if let job = open {
                        AgentDetail(model: model, job: job, floor: team.floor(of: job.id))
                            .id(job.id)
                    } else {
                        AgentsWelcome(model: model, assistant: assistant, settings: settings)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            }
            .padding(.top, 6)

            AgentJobField(model: model, assistant: assistant)
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
        case .queued: return Theme.tertiary
        case .working: return Theme.accent
        case .done: return Theme.good
        case .failed: return Theme.danger
        case .stopped: return Theme.warning
        }
    }

    static func symbol(_ status: AgentJob.Status) -> String {
        switch status {
        case .queued: return "clock.fill"
        case .working: return "circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .stopped: return "stop.circle.fill"
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

// MARK: The tower

/// Every agent, newest on top: the first job you ever gave is on floor 1.
struct AgentTower: View {
    @ObservedObject var model: NotchModel
    let team: AgentTeam

    var body: some View {
        let jobs = team.newestFirst
        let finished = jobs.filter { !$0.isActive }.count

        VStack(spacing: 0) {
            if let room = model.teamStore {
                TeamChatRow(store: room, selected: model.teamChatOpen, open: { model.openTeamChat() })
                    .padding(EdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 6))
            }
            if jobs.isEmpty {
                AgentTowerEmpty()
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(jobs) { job in
                            AgentFloorRow(job: job, floor: team.floor(of: job.id), selected: job.id == model.agentOpen && !model.teamChatOpen,
                                          open: { model.showAgent(job.id) })
                                .contextMenu { AgentMenu(model: model, job: job) }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.hidden)
                if finished > 0 {
                    AgentTowerFoot(finished: finished, clear: { model.clearFinishedAgents() })
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lane))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AgentTowerEmpty: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "building.2")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            Text("Nobody's working yet")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text("Your first agent takes floor 1. Each new one goes on top.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The bottom of the tower: how many have finished, and a way to clear them out.
struct AgentTowerFoot: View {
    let finished: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(finished == 1 ? "1 finished" : "\(finished) finished")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            Spacer(minLength: 4)
            SmallPill(title: "Clear", symbol: "xmark", action: clear)
                .help("Take the finished agents out of the room. The files they saved stay in their folders.")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(Theme.surface.opacity(0.6))
    }
}

/// One agent's floor: its number, its name, and what it's doing or how it ended.
struct AgentFloorRow: View {
    let job: AgentJob
    let floor: Int
    let selected: Bool
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                AgentFloorBadge(floor: floor, status: job.status)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(job.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if job.origin == .chief {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.tertiary)
                                .help("The assistant handed out this job")
                        }
                    }
                    Text(job.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(job.status == .failed ? Theme.danger : Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                AgentClock(job: job)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Theme.raised : (hovering ? Theme.hover.opacity(0.55) : Color.clear)))
            // The line joining the floors, like a lift shaft, behind their numbers.
            .background(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 2)
                    .padding(.leading, 21)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Floor \(floor), \(job.name), \(job.statusWord)"))
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
            .help("Floor \(floor): \(AgentFloorBadge.word(status))")
    }

    static func word(_ status: AgentJob.Status) -> String {
        switch status {
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

    var body: some View {
        if job.isActive {
            Button("Stop") { model.stopAgent(job.id) }
        } else {
            Button("Run Again") { model.agentAgain(job.id) }
        }
        if !job.folder.isEmpty {
            Button("Show Its Folder") { model.onShowAgentFolder?(job.id) }
        }
        if !job.isActive {
            Divider()
            Button("Remove from the Room") { model.removeAgent(job.id) }
        }
    }
}

// MARK: The team chat

/// The team chat's place at the top of the tower: its latest message.
struct TeamChatRow: View {
    @ObservedObject var store: TeamStore
    let selected: Bool
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        let last = store.room.messages.last

        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.avatar))
            VStack(alignment: .leading, spacing: 2) {
                Text("Team chat")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(last.map { "\($0.name): \(AgentStream.shorten($0.text, to: 60))" } ?? "Agents, the chief of staff and you")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Theme.raised : (hovering ? Theme.hover.opacity(0.55) : Theme.surface.opacity(0.6))))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help("The chat your agents share with the chief of staff and you")
    }
}

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
            AgentWords(text: message.text, colour: mine ? Theme.text : Theme.body)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(mine ? Theme.raised : Theme.lane))
    }

    static func who(_ message: TeamMessage) -> String {
        if case .agent(let name, let floor) = message.from {
            return "\(name) · floor \(floor)"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentHeader(model: model, job: job, floor: floor)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    AgentTask(task: job.task)
                    if let problem = job.problem, !problem.isEmpty {
                        AgentProblem(text: problem, failed: job.status == .failed)
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

    var body: some View {
        HStack(spacing: 11) {
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
            AgentActions(model: model, job: job)
        }
    }
}

/// Stop it while it works; afterwards copy its report, run it again, or take it out.
struct AgentActions: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    @State var copied = false

    var body: some View {
        HStack(spacing: 6) {
            if job.isActive {
                SmallPill(title: "Stop", symbol: "stop.fill", action: { model.stopAgent(job.id) })
                    .help("Stop this agent. What it has written so far is kept.")
            } else {
                if !job.report.isEmpty {
                    SmallPill(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", action: copy)
                        .help("Copy the report")
                }
                SmallPill(title: "Again", symbol: "arrow.clockwise", action: { model.agentAgain(job.id) })
                    .help("Give the same job to a new agent")
            }
            if !job.folder.isEmpty {
                SmallPill(title: "Folder", symbol: "folder", action: { model.onShowAgentFolder?(job.id) })
                    .help("Open this agent's folder in Finder")
            }
            if !job.isActive {
                IconButton(symbol: "trash", label: "Take this agent out of the room (its files stay in its folder)", size: 26,
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
            let lines = AgentReport.lines(report)
            VStack(alignment: .leading, spacing: 4) {
                AgentCaption(text: finished ? "Its report" : "What it's writing")
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(lines) { line in
                        AgentReportLine(line: line)
                    }
                }
                if AgentReport.isCut(report) {
                    Text("There's more: Copy has the whole report.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

struct AgentReportLine: View {
    let line: AgentReport.Line

    var body: some View {
        switch line.kind {
        case .heading(let level):
            AgentWords(text: line.text, size: level <= 1 ? 15 : (level == 2 ? 14 : 13), weight: .bold, colour: Theme.text)
                .padding(.top, 5)
        case .bullet(let indent):
            AgentListLine(mark: "•", text: line.text, indent: indent)
        case .numbered(let number, let indent):
            AgentListLine(mark: number, text: line.text, indent: indent)
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.tertiary)
                    .frame(width: 2)
                AgentWords(text: line.text, colour: Theme.secondary)
            }
        case .code:
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.text2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .row(let header):
            AgentWords(text: line.text, weight: header ? .semibold : .regular, colour: header ? Theme.text2 : Theme.body)
        case .rule:
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.vertical, 4)
        case .body:
            AgentWords(text: line.text)
        case .gap:
            Color.clear
                .frame(height: 4)
        }
    }
}

/// A bullet or a numbered line, hanging from its mark.
struct AgentListLine: View {
    let mark: String
    let text: String
    let indent: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark)
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            AgentWords(text: text)
        }
        .padding(.leading, CGFloat(indent) * 14)
    }
}

/// A line of an agent's words, with its bold, italics, code and links drawn.
struct AgentWords: View {
    let text: String
    var size: CGFloat = 12.5
    var weight: Font.Weight = .regular
    var colour: Color = Theme.body

    var body: some View {
        Text(ChatBubble.formatted(text))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(colour)
            .lineSpacing(2.5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: A new job

/// When no agent is picked: what the room is for, what agents can do, and jobs to try.
struct AgentsWelcome: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant
    @ObservedObject var settings: AppSettings

    var body: some View {
        let tools = assistant.engine == .claudeCode
        let needsSetup = !assistant.status.isReady && assistant.status != .checking

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 9) {
                Text("The agent room")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Hand a job to an agent and it works on it by itself while you get on with something else. Each agent gets a floor: watch what it's doing, then read its report. Or just ask the assistant, and it hands the big jobs out for you.")
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
                if needsSetup {
                    PillButton(title: "Set Up \(assistant.engine.name) First", prominent: true, action: { model.openAssistant() })
                } else {
                    AgentCaption(text: "Jobs to start from")
                        .padding(.top, 2)
                    HStack(spacing: 6) {
                        ForEach(AgentBrief.examples) { example in
                            SmallPill(title: example.title, symbol: example.symbol, action: { model.agentDraft = example.job })
                                .help(example.job)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
    }
}

/// The box along the bottom of the room: type a job, press Return, and a new agent starts on it.
struct AgentJobField: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var assistant: Assistant
    @FocusState private var typing: Bool

    init(model: NotchModel, assistant: Assistant) {
        self.model = model
        self.assistant = assistant
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(model.teamChatOpen ? "Say something to the team: the chief and every working agent can read it…"
                      : "Give an agent a job: what to find out, write or compare…", text: $model.agentDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1...4)
                .focused($typing)
                .onSubmit(start)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            IconButton(symbol: "arrow.up", label: model.teamChatOpen ? "Post it (Return)" : "Start an agent on it (Return)", size: 32,
                       tint: Theme.text, action: start)
        }
        .onAppear { typing = true }
    }

    private func start() {
        // Nothing can answer yet: the assistant's page says what to set up.
        if !assistant.status.isReady && assistant.status != .checking {
            model.openAssistant()
            return
        }
        model.sendAgentDraft()
        typing = true
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
                model.showAgent(job.id)
            }
            model.openAgents()
        }
        .onHover { hovering = $0 }
        .help("Open the agent room")
    }
}
