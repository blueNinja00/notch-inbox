import AppKit
import SwiftUI

// MARK: The side of the room

/// The side of the agent room: your groups, each with a bar showing how its tasks are
/// going, and under them the team chat, the library and your recipes.
struct AgentSidebar: View {
    @ObservedObject var model: NotchModel
    let team: AgentTeam
    /// Your shortcuts, for the tooltips.
    let keys: Keybinds

    var body: some View {
        let onGroups = model.agentsPage == .agent
        let open = team.group(model.agentGroupOpen)?.id

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AgentCaption(text: "Groups")
                Spacer(minLength: 4)
                if team.groups.count < AgentTeam.mostGroups {
                    IconButton(symbol: "plus", label: "New group" + keys.hint(for: .newGroup), size: 22, tint: Theme.tertiary,
                               action: { model.newGroup() })
                }
            }
            .padding(EdgeInsets(top: 7, leading: 12, bottom: 3, trailing: 6))
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(team.groupIDs, id: \.self) { id in
                        AgentGroupRow(name: team.groupName(id), tally: team.tally(in: id), selected: onGroups && open == id,
                                      open: { model.showGroup(id) })
                            .contextMenu {
                                AgentGroupMenu(model: model, group: id)
                            }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            AgentSidebarLinks(model: model, keys: keys)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lane))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One group in the list: its name, how many of its tasks are done, and its status bar.
struct AgentGroupRow: View {
    let name: String
    let tally: AgentTally
    let selected: Bool
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if tally.working > 0 {
                    AgentPulse(size: 5)
                }
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(tally.short)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            AgentStatusBar(tally: tally, height: 4)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help(tally.spoken(for: name))
        .accessibilityLabel(Text(tally.spoken(for: name)))
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        if selected {
            return Theme.raised
        }
        return hovering ? Theme.hover.opacity(0.55) : Color.clear
    }
}

/// A group's right-click menu.
struct AgentGroupMenu: View {
    @ObservedObject var model: NotchModel
    let group: UUID?

    var body: some View {
        Button("Open") { model.showGroup(group) }
        if let id = group {
            Button("Rename") {
                model.showGroup(id)
                model.focusAgents(.groupName)
            }
            Divider()
            Button("Delete This Group") { model.removeGroup(id) }
        }
    }
}

/// How a group is going, as a bar: green for what's done, then what's working, what's
/// waiting its turn, what couldn't finish and what was stopped. Tasks that haven't been
/// started are the empty rest of it.
struct AgentStatusBar: View {
    let tally: AgentTally
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                ForEach(tally.segments) { part in
                    AgentBarPart(status: part.status)
                        .frame(width: max(0, space.size.width * part.share))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Color.white.opacity(0.09))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// One stretch of a status bar. The stretch for what's working breathes.
struct AgentBarPart: View {
    let status: AgentJob.Status
    @State var dim = false

    var body: some View {
        Rectangle()
            .fill(AgentLook.bar(status))
            .opacity(status == .working && dim ? 0.4 : 1)
            .onAppear {
                guard status == .working else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

/// Under the groups: the team chat, the library and your recipes.
struct AgentSidebarLinks: View {
    @ObservedObject var model: NotchModel
    let keys: Keybinds

    var body: some View {
        VStack(spacing: 2) {
            if model.teamStore != nil {
                AgentSidebarLink(title: "Team chat", symbol: "bubble.left.and.bubble.right.fill", count: 0,
                                 selected: model.agentsPage == .teamChat,
                                 tip: "The chat your agents share with the chief of staff and you" + keys.hint(for: .teamChat),
                                 open: { model.openTeamChat() })
            }
            if let reports = model.reportsStore {
                AgentLibraryLink(model: model, reports: reports, keys: keys)
            }
            if model.recipesStore != nil {
                AgentSidebarLink(title: "Recipes", symbol: "text.book.closed.fill", count: 0,
                                 selected: model.agentsPage == .recipes,
                                 tip: "Jobs you hand out often, saved to run again" + keys.hint(for: .recipes),
                                 open: { model.openRecipes() })
            }
        }
        .padding(6)
    }
}

/// The library's place in the side of the room, with how many reports it holds.
struct AgentLibraryLink: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var reports: ReportsStore
    let keys: Keybinds

    var body: some View {
        AgentSidebarLink(title: "Library", symbol: "books.vertical.fill", count: reports.library.reports.count,
                         selected: model.agentsPage == .library,
                         tip: "Every report your agents have finished, kept to search and pin" + keys.hint(for: .library),
                         open: { model.openLibrary() })
    }
}

struct AgentSidebarLink: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    let tip: String
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.text : Theme.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Theme.text : Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help(tip)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        if selected {
            return Theme.raised
        }
        return hovering ? Theme.hover.opacity(0.55) : Color.clear
    }
}

// MARK: A group's tasks

/// The widths of the table's fixed columns. The task and its status share the rest.
enum AgentTable {
    static let number: CGFloat = 24
    static let time: CGFloat = 50
    static let actions: CGFloat = 50
    static let row: CGFloat = 38
}

/// One group: its name, its status bar, the buttons that act on all of it, and its tasks
/// as a table, newest on top.
struct AgentGroupView: View {
    @ObservedObject var model: NotchModel
    let team: AgentTeam
    let group: UUID?
    let keys: Keybinds

    var body: some View {
        let jobs = team.jobs(in: group)
        let held = team.heldForChains

        VStack(alignment: .leading, spacing: 8) {
            AgentGroupHeader(model: model, group: group, tally: AgentTally(jobs), clearable: team.clearable(in: group), keys: keys)
            if jobs.isEmpty {
                Text(AgentGroupView.emptyLine(team.groupName(group)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                AgentTableHead()
                ScrollViewReader { scroller in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            ForEach(jobs) { job in
                                AgentTaskRow(model: model, job: job, number: team.floor(of: job.id), picked: job.id == model.agentOpen,
                                             held: held.contains(job.id))
                                    .id(job.id)
                                    .contextMenu {
                                        AgentMenu(model: model, job: job, team: team, held: held.contains(job.id),
                                                  canCarryOn: team.canCarryOn(job.id))
                                    }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    // (A task picked with the keys is brought into view.)
                    .onChange(of: model.agentOpen) { picked in
                        if let picked = picked {
                            scroller.scrollTo(picked)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func emptyLine(_ name: String) -> String {
        "No tasks in \(name) yet. Type one in the box below and press Return: it waits here until you press Start."
    }
}

/// The top of a group: its name (type over it to change it), the buttons for all of its
/// tasks at once, and its status bar with the count behind it.
struct AgentGroupHeader: View {
    @ObservedObject var model: NotchModel
    let group: UUID?
    let tally: AgentTally
    let clearable: Int
    let keys: Keybinds
    @FocusState private var naming: Bool

    init(model: NotchModel, group: UUID?, tally: AgentTally, clearable: Int, keys: Keybinds) {
        self.model = model
        self.group = group
        self.tally = tally
        self.clearable = clearable
        self.keys = keys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let id = group {
                    TextField("Name this group", text: name(id))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .focused($naming)
                        .onSubmit { model.focusAgents(.box) }
                        .help("Type over the name to change it")
                } else {
                    Text(AgentGroup.general)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .help("Everything that's in no other group. It's always here.")
                }
                Spacer(minLength: 6)
                if tally.idle > 0 {
                    SmallPill(title: "Start All", symbol: "play.fill", action: { model.startGroup() })
                        .help("Start every task here that's ready" + keys.hint(for: .startAll))
                }
                if tally.active > 0 {
                    SmallPill(title: "Stop All", symbol: "stop.fill", action: { model.stopGroup() })
                        .help("Stop every task here that's working or waiting its turn. What they've written is kept." + keys.hint(for: .stopAll))
                }
                if clearable > 0 {
                    SmallPill(title: "Clear Done", symbol: "xmark", action: { model.clearGroup() })
                        .help("Take the finished tasks out of this group. Their reports stay in the Library." + keys.hint(for: .clearDone))
                }
                if let id = group {
                    IconButton(symbol: "trash", label: "Delete this group. Its tasks go to General.", size: 26,
                               action: { model.removeGroup(id) })
                }
            }
            HStack(spacing: 10) {
                AgentStatusBar(tally: tally, height: 6)
                    .frame(width: 170)
                Text(tally.line)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        // A new group, or Rename: its name is ready to type over.
        .onAppear(perform: takeFocus)
        .onChange(of: model.agentsFocusTick) { _ in
            takeFocus()
        }
    }

    private func takeFocus() {
        if group != nil, model.takeFocus(.groupName) {
            naming = true
        }
    }

    /// The group's name, read from the room as it's typed.
    private func name(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.agentsStore?.team.group(id)?.name ?? "" },
            set: { typed in model.renameGroup(id, to: typed) }
        )
    }
}

/// The names over the table's columns.
struct AgentTableHead: View {
    var body: some View {
        HStack(spacing: 10) {
            AgentCaption(text: "#")
                .frame(width: AgentTable.number, alignment: .leading)
            AgentCaption(text: "Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            AgentCaption(text: "Status")
                .frame(maxWidth: .infinity, alignment: .leading)
            AgentCaption(text: "Time")
                .frame(width: AgentTable.time, alignment: .trailing)
            Color.clear
                .frame(width: AgentTable.actions, height: 1)
        }
        .padding(.horizontal, 10)
    }
}

/// One task in the table: its number, its name, how it's going (in its state's colour,
/// with a line along the bottom that breathes while it works), how long it has taken,
/// and the buttons to start or stop it. Click it for its own page.
struct AgentTaskRow: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    let number: Int
    let picked: Bool
    /// A chain still going is built on its work, so it can't be taken out yet.
    let held: Bool
    @State var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .frame(width: AgentTable.number, alignment: .leading)
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
                if let chain = job.chain {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .help("\(chain.place) of a chain: \(chain.line)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AgentStatusCell(job: job)
                .frame(maxWidth: .infinity, alignment: .leading)
            AgentClock(job: job)
                .frame(width: AgentTable.time, alignment: .trailing)
            AgentRowActions(model: model, job: job, held: held)
                .frame(width: AgentTable.actions, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: AgentTable.row)
        .background(fill)
        .overlay(alignment: .bottom) {
            AgentRowBar(status: job.status)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { model.showAgent(job.id) }
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Task \(number), \(job.name), \(job.statusLabel)"))
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        if picked {
            return Theme.raised
        }
        return hovering ? Theme.hover.opacity(0.55) : Theme.lane.opacity(0.55)
    }
}

/// How a task is going, in the colour of its state, and more quietly what came of it.
struct AgentStatusCell: View {
    let job: AgentJob

    var body: some View {
        let note = job.statusNote

        HStack(spacing: 6) {
            if job.status == .working {
                AgentPulse(size: 6)
            } else {
                Image(systemName: AgentLook.symbol(job.status))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AgentLook.tint(job.status))
            }
            (Text(job.statusLabel).foregroundColor(AgentLook.ink(job.status))
                + Text(note.isEmpty ? "" : "  " + note).foregroundColor(Theme.tertiary))
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
        }
        .help(note.isEmpty ? job.statusLabel : "\(job.statusLabel): \(note)")
    }
}

/// The line along the bottom of a task's row: its state's colour, breathing while it works.
struct AgentRowBar: View {
    let status: AgentJob.Status
    @State var dim = false

    var body: some View {
        Rectangle()
            .fill(AgentLook.bar(status))
            .frame(height: 2)
            .opacity(status == .working && dim ? 0.3 : 1)
            .onAppear(perform: breathe)
            .onChange(of: status) { _ in
                breathe()
            }
            .accessibilityHidden(true)
    }

    private func breathe() {
        if status == .working {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dim = true
            }
        } else {
            withAnimation(.linear(duration: 0.1)) {
                dim = false
            }
        }
    }
}

/// At the end of a task's row: start it, stop it or run it again, and take it out.
struct AgentRowActions: View {
    @ObservedObject var model: NotchModel
    let job: AgentJob
    let held: Bool

    var body: some View {
        HStack(spacing: 0) {
            if job.isIdle {
                IconButton(symbol: "play.fill", label: "Start this task", size: 24, tint: Theme.text2,
                           action: { model.startTask(job.id) })
            } else if job.isActive {
                IconButton(symbol: "stop.fill", label: "Stop it. What it has written is kept.", size: 24, tint: Theme.text2,
                           action: { model.stopAgent(job.id) })
            } else {
                IconButton(symbol: "arrow.clockwise", label: "Run it again, as a new task", size: 24, tint: Theme.text2,
                           action: { model.agentAgain(job.id) })
            }
            if !job.isActive && !held {
                IconButton(symbol: "trash", label: AgentRowActions.removeLabel(job), size: 24, tint: Theme.tertiary,
                           action: { model.removeAgent(job.id) })
            }
        }
    }

    static func removeLabel(_ job: AgentJob) -> String {
        job.isIdle ? "Remove this task" : "Take it out of the room. Its report stays in the Library, and its files in its folder."
    }
}
