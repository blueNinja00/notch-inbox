import Foundation
#if canImport(Combine)
import Combine
#endif

/// Everything the notch UI renders from. Starts with sample mail; once the browser
/// add-on delivers real Gmail, `showLive` swaps it in.
final class NotchModel: ObservableObject {
    @Published var level: NotchLevel = .rest
    @Published var metrics: NotchMetrics
    @Published private(set) var accounts: [MailAccount]
    /// Every message of the inboxes shown. Real mail arrives newest first.
    @Published private(set) var messages: [MailMessage] {
        didSet { regroup() }
    }
    /// Each inbox's messages, newest first, worked out once whenever the mail changes
    /// (the notch can hold thousands).
    private var inboxes: [String: [MailMessage]] = [:]
    /// The newest messages across the inboxes, for the primary menu and the assistant.
    private(set) var recent: [MailMessage] = []
    @Published private(set) var activeAccountID: String
    @Published private(set) var openMessageID: String?
    @Published private(set) var replyFromID: String?
    @Published var replyText: String = ""
    @Published private(set) var sentFrom: String?

    /// True until real mail arrives from the browser link.
    @Published private(set) var isSample = true
    /// Gmail's own unread counts per account (the feed lists only the newest ~20).
    @Published private(set) var reportedUnread: [String: Int] = [:]

    /// A newer build that's ready to install, if any. Shows as an Update button in the notch.
    @Published var pendingUpdate: Int? = nil
    var onInstallUpdate: (() -> Void)?
    /// Opens a link in the browser (set by the app).
    var onOpenURL: ((URL) -> Void)?

    /// A short update status shown beside the panel buttons after Check for Updates.
    @Published var updateNote: String? = nil

    /// Tells the app you opened a real email, so its whole text is fetched first.
    var onOpenMessage: ((String) -> Void)?
    /// Real mail's read and unread are kept by the app (Gmail itself isn't changed): one
    /// email, a whole inbox, and undoing the last "Mark all".
    var onSetRead: ((String, Bool) -> Void)?
    var onMarkAll: ((String, Bool) -> Void)?
    var onUndoMarkAll: (() -> Void)?
    /// The inbox whose last "Mark all read" or "Mark all unread" can be undone.
    @Published var undoAccount: String?

    /// Searching Mail: the box under the top row, and what's typed in it.
    @Published var searching = false
    @Published var searchText = ""

    /// What the browser add-on does about whole emails, for the note under Gmail's previews.
    enum WholeEmails: Equatable {
        /// Fetched within a minute or so.
        case coming
        /// Fetched once you open them here, because Gmail then counts them as read.
        case whenOpened
        /// The browser still runs add-on 1.0, which can't fetch them.
        case addOnNeedsReload
    }

    @Published var wholeEmails: WholeEmails = .coming

    /// An inbox that's linked but isn't in the notch: what "Add an inbox" offers.
    struct SpareInbox: Identifiable, Equatable {
        let id: String
        let name: String
    }

    /// The most inboxes the notch shows side by side.
    static let mostInboxes = LiveMailbox.maxAccounts

    /// Inboxes you could add to the notch.
    @Published private(set) var spareInboxes: [SpareInbox] = []
    /// For your own mail, the app keeps which inboxes show and in what order, for every screen.
    var onShowInbox: ((String) -> Void)?
    var onHideInbox: ((String) -> Void)?
    var onMoveInbox: ((String, Int) -> Void)?

    /// Every sample inbox, and the ones showing, in order. Sample mail starts with one
    /// inbox, the way your own mail does.
    private let sampleAccounts: [MailAccount]
    private var sampleShown: [String]

    init(provider: MailProvider, metrics: NotchMetrics) {
        let all = provider.accounts()
        let first = Array(all.prefix(1))
        sampleAccounts = all
        sampleShown = first.map { $0.id }
        self.accounts = NotchModel.numbered(first)
        self.messages = provider.messages()
        self.metrics = metrics
        self.activeAccountID = first.first?.id ?? ""
        spareInboxes = all.dropFirst().map { SpareInbox(id: $0.id, name: $0.name) }
        regroup()
    }

    // MARK: Which inboxes show

    /// Whether there's room for another inbox, and one to add.
    var canAddInbox: Bool {
        accounts.count < NotchModel.mostInboxes && !spareInboxes.isEmpty
    }

    /// Puts another inbox in the notch, after the ones already there.
    func showInbox(_ id: String) {
        guard accounts.count < NotchModel.mostInboxes, spareInboxes.contains(where: { $0.id == id }) else { return }
        if isSample {
            sampleShown.append(id)
            refreshSample()
        } else {
            onShowInbox?(id)
        }
    }

    /// Takes an inbox out of the notch. Its mail is kept, and it can be added back. The
    /// last inbox stays.
    func hideInbox(_ id: String) {
        guard accounts.count > 1, accounts.contains(where: { $0.id == id }) else { return }
        if isSample {
            sampleShown.removeAll { $0 == id }
            refreshSample()
        } else {
            onHideInbox?(id)
        }
    }

    /// Whether an inbox can move one place left (-1) or right (1).
    func canMoveInbox(_ id: String, by offset: Int) -> Bool {
        LiveMailbox.neighbour(of: id, by: offset, among: accounts.map { $0.id }) != nil
    }

    /// Moves an inbox one place left or right.
    func moveInbox(_ id: String, by offset: Int) {
        guard canMoveInbox(id, by: offset) else { return }
        if isSample {
            guard let index = sampleShown.firstIndex(of: id) else { return }
            sampleShown.swapAt(index, index + offset)
            refreshSample()
        } else {
            onMoveInbox?(id, offset)
        }
    }

    /// Sample mail: the inboxes showing changed.
    private func refreshSample() {
        let shown = sampleShown.compactMap { id in sampleAccounts.first { $0.id == id } }
        accounts = NotchModel.numbered(shown)
        spareInboxes = sampleAccounts.filter { !sampleShown.contains($0.id) }.map { SpareInbox(id: $0.id, name: $0.name) }
        if !accounts.contains(where: { $0.id == activeAccountID }) {
            activeAccountID = accounts.first?.id ?? ""
            openMessageID = nil
            replyFromID = nil
            if level == .detail {
                level = .lanes
            }
        }
        regroup()
    }

    /// Inboxes numbered 1, 2, 3 in the order they show: the keys that open them.
    private static func numbered(_ accounts: [MailAccount]) -> [MailAccount] {
        accounts.enumerated().map { index, account in
            var numbered = account
            numbered.shortcut = String(index + 1)
            return numbered
        }
    }

    /// Real Gmail arrives read-only: archive and reply happen in Gmail. (Read and unread are
    /// the notch's own, so those work on real mail too.)
    var canAct: Bool { isSample }

    /// Swap in real accounts and mail from the browser link. `spare` is the linked inboxes
    /// that aren't in the notch.
    func showLive(accounts: [MailAccount], messages: [MailMessage], unread: [String: Int], spare: [SpareInbox] = []) {
        let wasSample = isSample
        self.accounts = accounts
        self.messages = messages
        reportedUnread = unread
        isSample = false
        if spareInboxes != spare {
            spareInboxes = spare
        }

        let lostOpenInbox = !wasSample && !accounts.contains(where: { $0.id == activeAccountID })
        if wasSample || lostOpenInbox {
            activeAccountID = accounts.first?.id ?? ""
            openMessageID = nil
            replyFromID = nil
            sentFrom = nil
        }
        // The inbox you had open was taken out of the notch: back to the ones still in it.
        if lostOpenInbox, tool == .mail, level == .detail {
            level = .lanes
        }
        if let id = openMessageID, !messages.contains(where: { $0.id == id }) {
            openMessageID = nil
        }
        if accounts.isEmpty, level == .detail {
            level = .lanes
        }
    }

    // MARK: Reading

    /// Messages in one inbox, newest first.
    func inbox(_ accountID: String) -> [MailMessage] {
        inboxes[accountID] ?? []
    }

    private func regroup() {
        var groups: [String: [MailMessage]] = [:]
        var inOrder = true
        var previous: Date?
        for message in messages {
            groups[message.accountID, default: []].append(message)
            if let previous = previous, message.date > previous {
                inOrder = false
            }
            previous = message.date
        }
        if !inOrder {
            for (account, list) in groups {
                groups[account] = list.sorted { $0.date > $1.date }
            }
        }
        inboxes = groups
        let shown = Set(accounts.map { $0.id })
        let newest = inOrder ? messages : messages.sorted { $0.date > $1.date }
        recent = Array(newest.lazy.filter { shown.contains($0.accountID) }.prefix(60))
    }

    // MARK: Searching

    /// Opens the search box in Mail.
    func startSearch() {
        tool = .mail
        if level == .rest || level == .peek {
            level = .lanes
        }
        searching = true
    }

    func endSearch() {
        searching = false
        searchText = ""
    }

    /// The words being searched for, lowercased.
    var searchWords: [String] {
        guard searching else { return [] }
        return searchText.lowercased().split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    }

    /// An inbox's messages, or while you're searching, the ones that match: every word has
    /// to be in the sender, their address, the subject or the preview.
    func shownInbox(_ accountID: String) -> [MailMessage] {
        let words = searchWords
        guard !words.isEmpty else { return inbox(accountID) }
        return inbox(accountID).filter { NotchModel.matches($0, words: words) }
    }

    static func matches(_ message: MailMessage, words: [String]) -> Bool {
        let text = [message.sender, message.senderEmail, message.subject, message.snippet].joined(separator: " ").lowercased()
        return words.allSatisfy { text.contains($0) }
    }

    func unreadCount(_ accountID: String) -> Int {
        if let reported = reportedUnread[accountID] {
            return reported
        }
        return messages.filter { $0.accountID == accountID && $0.isUnread }.count
    }

    var totalUnread: Int {
        accounts.reduce(0) { $0 + unreadCount($1.id) }
    }

    /// Minimised to the floating mail icon: nothing shows at the notch until you open it.
    @Published var minimised = false
    var onMinimise: ((Bool) -> Void)?

    func setMinimised(_ on: Bool) {
        onMinimise?(on)
    }

    // MARK: Tools and sizes

    /// Which tool the open panel shows. Inboxes and notes both use the lanes and detail sizes.
    enum Tool: Equatable {
        case mail
        case planner
        case notes
        case assistant
        case timetable
        case extras
        case bookmarks
        case assignments
        case agents
        case settings
        /// The tour of what everything does.
        case tour
    }

    @Published var tool: Tool = .mail
    /// The Settings section showing.
    @Published var settingsSection: SettingsSection = .general
    /// The notes, shared by every screen (set by the app).
    var notesStore: NotesStore?
    @Published var selectedNoteID: UUID?

    /// The timetable, shared by every screen (set by the app).
    var timetableStore: TimetableStore?

    /// What the timetable's side panel is editing.
    enum TimetableEdit: Equatable {
        case lesson(Timetable.Slot)
        case period(UUID)
    }

    @Published var timetableEdit: TimetableEdit? {
        didSet {
            // Finished with a lesson: trim what was typed and drop anything left blank.
            if oldValue != nil && oldValue != timetableEdit {
                timetableStore?.change { $0.tidy() }
            }
        }
    }

    /// Which week of a two-week timetable is on screen: 0 for Week A, 1 for Week B.
    @Published var timetableWeek = 0

    /// The shelf of parked files, shared by every screen (set by the app).
    var shelfStore: ShelfStore?

    /// The planner (homework and exams), shared by every screen (set by the app).
    var plannerStore: PlannerStore?

    /// What the planner's side panel is editing.
    enum PlannerEdit: Equatable {
        case task(UUID)
        case exam(UUID)
    }

    @Published var plannerEdit: PlannerEdit? {
        didSet {
            // Finished with one: homework or an exam left without a name goes.
            if let before = oldValue, before != plannerEdit {
                removeIfUnnamed(before)
            }
        }
    }
    /// Whether the planner's list shows finished homework as well.
    @Published var plannerShowsDone = false

    /// Sizes you've dragged each open level to; missing means the standard size.
    @Published var customSizes: [NotchLevel: CGSize] = [:]
    /// Called when you let go after dragging, to remember the size and share it.
    var onResized: (([NotchLevel: CGSize]) -> Void)?

    /// Whether the primary menu has its row of extras (now playing, focus, clipboard, shelf).
    @Published var showsExtras = false
    /// A focus timer is running: its minutes show beside the closed notch.
    @Published var focusRunning = false

    /// The panel's size at a level: as dragged, else standard.
    func size(_ level: NotchLevel) -> CGSize {
        guard level != .rest, let custom = customSizes[level] else {
            return metrics.bodySize(level, ears: restEars, extras: showsExtras, tiles: homeMenu.shown.count)
        }
        return metrics.clamp(custom, for: level)
    }

    // MARK: The primary menu's tiles

    /// Which tools have a tile on the primary menu, and in what order. The app keeps it,
    /// for every screen.
    @Published var homeMenu = HomeMenu.standard
    /// Asks the app to rearrange the primary menu.
    var onArrangeHome: ((HomeMenu) -> Void)?

    /// Moves a tile one place left (-1) or right (1) among the tiles showing.
    func moveTile(_ tile: HomeTile, by offset: Int) {
        var menu = homeMenu
        guard menu.move(tile, by: offset, amongShown: true) else { return }
        arrangeHome(menu)
    }

    /// Takes a tile off the primary menu (Settings → General puts it back). The last one stays.
    func hideTile(_ tile: HomeTile) {
        var menu = homeMenu
        guard menu.setShown(tile, false) else { return }
        arrangeHome(menu)
    }

    private func arrangeHome(_ menu: HomeMenu) {
        if let ask = onArrangeHome {
            ask(menu)
        } else {
            homeMenu = menu
        }
    }

    /// Opens the tool a tile stands for.
    func open(_ tile: HomeTile) {
        switch tile {
        case .mail: openLanes()
        case .planner: openPlanner()
        case .assignments: openAssignments()
        case .timetable: openTimetable()
        case .notes: openNotes()
        case .assistant: openAssistant()
        case .agents: openAgents()
        case .bookmarks: openBookmarks()
        }
    }

    // MARK: Agents

    /// Your agents and their jobs, shared by every screen (set by the app).
    var agentsStore: AgentsStore?

    /// The task that's picked out in the Agents room: the one its shortcuts act on.
    @Published var agentOpen: UUID?
    /// Whether the picked task's own page (its job, what it did, its report) is showing in
    /// place of its group's table.
    @Published var agentShowsWork = false
    /// The group whose tasks are showing; nil is the first group, General.
    @Published var agentGroupOpen: UUID?

    /// Somewhere in the room to put the typing cursor.
    enum AgentsFocus: Equatable {
        /// The box a new task is typed in.
        case box
        case groupName
        case search
    }

    /// Where a shortcut or a button last asked for the cursor, and a count that goes up
    /// each time it's asked, so that asking twice for the same place still counts.
    @Published private(set) var agentsFocus: AgentsFocus?
    @Published private(set) var agentsFocusTick = 0

    func focusAgents(_ place: AgentsFocus) {
        agentsFocus = place
        agentsFocusTick += 1
    }

    /// For the view that owns a place: whether the cursor was asked for there. Asking
    /// uses the request up.
    func takeFocus(_ place: AgentsFocus) -> Bool {
        guard agentsFocus == place else { return false }
        agentsFocus = nil
        return true
    }
    /// The job being typed for a new agent.
    @Published var agentDraft = ""
    /// Whether the job in the box goes to a chain: a researcher, a writer, then a checker.
    /// It switches itself off after each chain, since a chain uses three agents' worth.
    @Published var agentDraftChain = false

    /// What shows beside the tower in the agent room.
    enum AgentsPage: Equatable {
        /// The agent you picked (or, with none picked, what the room is for).
        case agent
        case teamChat
        /// Every finished report, kept to find again.
        case library
        /// Jobs saved to run again.
        case recipes
    }

    @Published var agentsPage = AgentsPage.agent

    /// The team chat agents share with the chief of staff and you (set by the app).
    var teamStore: TeamStore?
    /// Whether the team chat is showing in the agent room, in place of one agent.
    var teamChatOpen: Bool {
        get { agentsPage == .teamChat }
        set {
            if newValue {
                agentsPage = .teamChat
            } else if agentsPage == .teamChat {
                agentsPage = .agent
            }
        }
    }
    var onPostToTeam: ((String) -> Void)?
    var onClearTeamChat: (() -> Void)?

    func openTeamChat() {
        tool = .agents
        teamChatOpen = true
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Return in the agent room's box: a message to the team while the chat is showing,
    /// otherwise a job for a new agent.
    func sendAgentDraft() {
        guard teamChatOpen else {
            addDraftedTask()
            return
        }
        let said = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        agentDraft = ""
        if let post = onPostToTeam {
            post(said)
        } else {
            teamStore?.change { $0.post(said, from: .you) }
        }
    }

    /// The job in the box joins the group that's showing, ready to start: it waits there
    /// until you press Start on it or on its group.
    func addDraftedTask() {
        if addTask(agentDraft, chain: agentDraftChain) {
            agentDraft = ""
            agentDraftChain = false
        }
    }

    /// Adds a task to the group that's showing without starting it. Returns false if
    /// there was nothing to add.
    @discardableResult
    func addTask(_ task: String, name: String = "", chain: Bool = false) -> Bool {
        let brief = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty, let store = agentsStore else { return false }
        let group = store.team.group(agentGroupOpen)?.id
        var added: AgentJob?
        store.change { team in
            if chain {
                added = team.addChain(title: name, goal: brief, kind: .write, group: group, start: false)
            } else {
                added = team.add(name: name, task: brief, group: group, start: false)
            }
        }
        agentsPage = .agent
        agentShowsWork = false
        agentGroupOpen = group
        agentOpen = added?.id ?? agentOpen
        return true
    }

    /// Hands the job in the box to a new agent, or to a chain of them, straight away.
    func startDraftedAgent() {
        if agentDraftChain {
            if startChain(goal: agentDraft) {
                agentDraft = ""
                agentDraftChain = false
            }
        } else if startAgent(task: agentDraft) {
            agentDraft = ""
        }
    }

    /// The app runs the agents; without it (in checks) jobs are only listed.
    var onStartAgent: ((String, String) -> UUID?)?
    /// Starts a chain on a job (its name, then the job), or carries one on from a stage
    /// that stopped short. Set by the app.
    var onStartChain: ((String, String) -> UUID?)?
    var onCarryOnChain: ((UUID) -> UUID?)?
    /// Has agents research an assignment (set by the app).
    var onResearchAssignment: ((UUID) -> UUID?)?
    /// Starts a task that was waiting, starts or stops a whole group, or clears a group's
    /// finished tasks (set by the app, which runs the agents).
    var onStartWaiting: ((UUID) -> Void)?
    var onStartGroup: ((UUID?) -> Void)?
    var onStopGroup: ((UUID?) -> Void)?
    var onClearGroup: ((UUID?) -> Void)?
    /// Whether the assistant is set up to do the work (set by the app). If it isn't,
    /// pressing Start opens its page, which says what to set up.
    var agentsCanStart: (() -> Bool)?
    var onStopAgent: ((UUID) -> Void)?
    var onAgentAgain: ((UUID) -> UUID?)?
    var onRemoveAgent: ((UUID) -> Void)?
    var onClearAgents: (() -> Void)?
    /// Shows an agent's folder, or opens one of the files it saved (set by the app).
    var onShowAgentFolder: ((UUID) -> Void)?
    var onOpenAgentFile: ((UUID, String) -> Void)?

    /// The Agents room: your groups down the side, and the tasks of the one you pick.
    func openAgents() {
        tool = .agents
        settleAgents()
        level = .lanes
    }

    /// Keeps what's picked real: a group that's still there, and a task that's in it.
    private func settleAgents() {
        guard let team = agentsStore?.team else { return }
        agentGroupOpen = team.group(agentGroupOpen)?.id
        if let picked = team.job(agentOpen) {
            agentGroupOpen = team.group(picked.group)?.id
        } else {
            agentOpen = team.jobs(in: agentGroupOpen).first?.id
            agentShowsWork = false
        }
    }

    func expandAgents() {
        tool = .agents
        level = .detail
    }

    /// Shows an agent's floor. One that has left the room is shown in the library, where
    /// its report is kept.
    func showAgent(_ id: UUID) {
        if agentsStore?.team.job(id) == nil, let kept = reportsStore?.library.entry(holding: id) {
            showReport(kept.id, part: kept.parts.first { $0.id == id }?.id)
            return
        }
        tool = .agents
        agentsPage = .agent
        agentOpen = id
        agentShowsWork = true
        if let job = agentsStore?.team.job(id) {
            agentGroupOpen = agentsStore?.team.group(job.group)?.id
        }
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Back from a task's own page to its group's table. The task stays picked.
    func closeAgent() {
        agentShowsWork = false
    }

    /// Picks a task in the table without opening it.
    func pickAgent(_ id: UUID) {
        guard let job = agentsStore?.team.job(id) else { return }
        agentsPage = .agent
        agentGroupOpen = agentsStore?.team.group(job.group)?.id
        agentOpen = id
    }

    // MARK: Groups

    /// Shows a group's tasks (nil: the first group, General).
    func showGroup(_ id: UUID?) {
        tool = .agents
        agentsPage = .agent
        agentShowsWork = false
        let group = agentsStore?.team.group(id)?.id
        if group != agentGroupOpen || agentsStore?.team.job(agentOpen) == nil {
            agentGroupOpen = group
            agentOpen = agentsStore?.team.jobs(in: group).first?.id
        }
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// A new group, opened with its name ready to type over. (Nothing happens once
    /// there are as many groups as there can be.)
    func newGroup() {
        guard let store = agentsStore else { return }
        var made: AgentGroup?
        store.change { made = $0.addGroup() }
        guard let group = made else { return }
        showGroup(group.id)
        focusAgents(.groupName)
    }

    func renameGroup(_ id: UUID, to name: String) {
        agentsStore?.change { $0.renameGroup(id, to: name) }
    }

    /// Takes a group away. Its tasks go to General.
    func removeGroup(_ id: UUID) {
        agentsStore?.change { $0.removeGroup(id) }
        if agentGroupOpen == id {
            agentGroupOpen = nil
            settleAgents()
        }
    }

    /// Moves a task to another group, and follows it there if it was the one picked.
    func moveAgent(_ id: UUID, to group: UUID?) {
        agentsStore?.change { $0.move(id, to: group) }
        if agentOpen == id, !agentShowsWork {
            agentOpen = agentsStore?.team.jobs(in: agentGroupOpen).first?.id
        } else if agentOpen == id {
            agentGroupOpen = agentsStore?.team.group(group)?.id
        }
    }

    /// A copy of a task, added to the same group, ready to start. (Not research for an
    /// assignment: that's started from the assignment.)
    func duplicateAgent(_ id: UUID) {
        guard let store = agentsStore, let job = store.team.job(id), Recipe.canSave(job) else { return }
        var added: AgentJob?
        store.change { team in
            if let chain = job.chain {
                added = team.addChain(title: chain.title, goal: job.task, kind: chain.kind, group: job.group, start: false)
            } else {
                added = team.add(name: job.name, task: job.task, group: job.group, start: false)
            }
        }
        guard let copy = added else { return }
        agentsPage = .agent
        agentShowsWork = false
        agentGroupOpen = store.team.group(copy.group)?.id
        agentOpen = copy.id
    }

    /// Changes what a task that hasn't started will be asked to do, as it's typed.
    func rewriteTask(_ id: UUID, to task: String) {
        agentsStore?.change { $0.rewrite(id, task: task) }
    }

    /// Whether the work can start. If the assistant isn't set up, its page opens to say
    /// what's missing, and nothing starts.
    private func readyToStart() -> Bool {
        if agentsCanStart?() == false {
            openAssistant()
            return false
        }
        return true
    }

    /// Start on a task that was waiting in its group.
    func startTask(_ id: UUID) {
        guard agentsStore?.team.job(id)?.isIdle == true, readyToStart() else { return }
        if let start = onStartWaiting {
            start(id)
        } else {
            agentsStore?.change { $0.start(id) }
        }
    }

    /// Start on every task waiting in the group that's showing.
    func startGroup() {
        guard let team = agentsStore?.team, team.tally(in: agentGroupOpen).idle > 0, readyToStart() else { return }
        if let start = onStartGroup {
            start(agentGroupOpen)
        } else {
            agentsStore?.change { $0.startAll(in: agentGroupOpen) }
        }
    }

    /// Stop everything in the group that's showing that's working or waiting its turn.
    func stopGroup() {
        if let stop = onStopGroup {
            stop(agentGroupOpen)
        } else if let team = agentsStore?.team {
            for job in team.jobs(in: agentGroupOpen) where job.isActive {
                stopAgent(job.id)
            }
        }
    }

    /// Takes the finished tasks out of the group that's showing. Their reports stay in
    /// the library.
    func clearGroup() {
        if let clear = onClearGroup {
            clear(agentGroupOpen)
        } else {
            agentsStore?.change { $0.clearFinished(in: agentGroupOpen) }
        }
        if agentsStore?.team.job(agentOpen) == nil {
            agentOpen = agentsStore?.team.jobs(in: agentGroupOpen).first?.id
            agentShowsWork = false
        }
    }

    /// Picks the next task down the table (or the one above), without opening it.
    func pickTask(by offset: Int) {
        guard let team = agentsStore?.team else { return }
        agentsPage = .agent
        if let next = team.job(after: agentOpen, in: agentGroupOpen, by: offset) {
            agentOpen = next
        }
    }

    // MARK: Shortcuts

    /// The shortcut being set in Settings: the next keys pressed become its key.
    @Published var recordingKey: KeyAction?
    /// What happened the last time a key was set, or why it couldn't be.
    @Published var keyNote: String?

    /// Does what a shortcut is for. False if it has nothing to act on right now.
    @discardableResult
    func perform(_ action: KeyAction) -> Bool {
        let team = agentsStore?.team
        let picked = team?.job(agentOpen)
        switch action {
        case .goHome: goHome()
        case .goMail: open(.mail)
        case .goPlanner: open(.planner)
        case .goTimetable: open(.timetable)
        case .goAssignments: open(.assignments)
        case .goNotes: open(.notes)
        case .goAssistant: open(.assistant)
        case .goAgents: open(.agents)
        case .goBookmarks: open(.bookmarks)
        case .goSettings: openSettings()
        case .newTask:
            agentsPage = .agent
            agentShowsWork = false
            focusAgents(.box)
        case .newGroup:
            newGroup()
        case .startAll:
            startGroup()
        case .stopAll:
            stopGroup()
        case .clearDone:
            clearGroup()
        case .nextTask:
            pickTask(by: 1)
        case .previousTask:
            pickTask(by: -1)
        case .nextGroup:
            showGroup(team?.group(after: agentGroupOpen, by: 1))
        case .previousGroup:
            showGroup(team?.group(after: agentGroupOpen, by: -1))
        case .chain:
            agentDraftChain.toggle()
        case .library:
            openLibrary()
        case .recipes:
            openRecipes()
        case .teamChat:
            openTeamChat()
        case .searchLibrary:
            if agentsPage != .library || reportOpen != nil {
                agentsPage = .library
                closeReport()
            }
            focusAgents(.search)
        case .toggleTask:
            guard agentsPage == .agent, let job = picked else { return false }
            if job.isIdle {
                startTask(job.id)
            } else if job.isActive {
                stopAgent(job.id)
            } else {
                return false
            }
        case .againTask:
            guard agentsPage == .agent, let job = picked, job.isFinished else { return false }
            agentAgain(job.id)
        case .openTask:
            guard agentsPage == .agent, picked != nil else { return false }
            agentShowsWork.toggle()
        case .removeTask:
            guard agentsPage == .agent, let job = picked, !job.isActive, team?.heldForChains.contains(job.id) != true else { return false }
            removeAgent(job.id)
        }
        return true
    }

    /// Gives an agent a job you typed. Returns false if nothing was typed.
    @discardableResult
    func startAgent(task: String, name: String = "") -> Bool {
        let brief = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { return false }
        agentsPage = .agent
        agentShowsWork = false
        if let start = onStartAgent {
            if let id = start(name, brief) {
                agentsStore?.change { $0.move(id, to: agentGroupOpen) }
                agentOpen = id
            }
        } else if let store = agentsStore {
            var added: AgentJob?
            store.change { added = $0.add(name: name, task: brief, group: agentGroupOpen) }
            agentOpen = added?.id ?? agentOpen
        }
        return true
    }

    /// Gives a job to a chain of agents: the researcher starts, and the others follow by
    /// themselves. Returns false if nothing was typed.
    @discardableResult
    func startChain(goal: String, title: String = "") -> Bool {
        let task = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return false }
        agentsPage = .agent
        agentShowsWork = false
        if let start = onStartChain {
            if let id = start(title, task) {
                agentsStore?.change { $0.move(id, to: agentGroupOpen) }
                agentOpen = id
            }
        } else if let store = agentsStore {
            var added: AgentJob?
            store.change { added = $0.addChain(title: title, goal: task, kind: .write, group: agentGroupOpen) }
            agentOpen = added?.id ?? agentOpen
        }
        return true
    }

    /// A stage of a chain stopped short: the next agent starts from what it left.
    func carryOnChain(_ id: UUID) {
        agentsPage = .agent
        if let carryOn = onCarryOnChain {
            if let new = carryOn(id) {
                agentOpen = new
            }
        } else if let store = agentsStore {
            var added: AgentJob?
            store.change { added = $0.carryOn(id) }
            agentOpen = added?.id ?? agentOpen
        }
    }

    /// "Research This" on an assignment: a researcher, a planner and a checker take it on
    /// in turn, working from its task sheet. You stay on the assignment, which says how
    /// they're going.
    func researchAssignment(_ id: UUID) {
        guard let item = assignmentsStore?.assignments.item(id), AgentChain.canResearch(item) else { return }
        if let research = onResearchAssignment {
            _ = research(id)
        } else {
            agentsStore?.change { team in
                team.addChain(title: item.title, goal: AgentChain.goal(for: item, now: Date()), kind: .assignment, source: id)
            }
        }
    }

    func stopAgent(_ id: UUID) {
        if let stop = onStopAgent {
            stop(id)
        } else {
            agentsStore?.change { $0.stop(id) }
        }
    }

    /// The same job again, as a new agent on top.
    func agentAgain(_ id: UUID) {
        if let again = onAgentAgain {
            if let new = again(id) {
                agentOpen = new
            }
        } else if let store = agentsStore {
            var added: AgentJob?
            store.change { added = $0.again(id) }
            agentOpen = added?.id ?? agentOpen
        }
    }

    func removeAgent(_ id: UUID) {
        if let remove = onRemoveAgent {
            remove(id)
        } else {
            agentsStore?.change { $0.remove(id) }
        }
        if agentsStore?.team.job(agentOpen) == nil {
            agentOpen = agentsStore?.team.jobs(in: agentGroupOpen).first?.id
            agentShowsWork = false
        }
    }

    func clearFinishedAgents() {
        if let clear = onClearAgents {
            clear()
        } else {
            agentsStore?.change { $0.clearFinished() }
        }
        if agentsStore?.team.job(agentOpen) == nil {
            agentOpen = agentsStore?.team.jobs(in: agentGroupOpen).first?.id
            agentShowsWork = false
        }
    }

    /// Esc in the agent room: back from a task's own page to its group, from an open report
    /// or recipe to its list, or out of a search of the library. False if there was
    /// nothing to step back from.
    func stepBackInAgents() -> Bool {
        if agentsPage == .agent, agentShowsWork, agentsStore?.team.job(agentOpen) != nil {
            closeAgent()
            return true
        }
        if agentsPage == .library, reportOpen != nil {
            closeReport()
            return true
        }
        // (From the list, it first clears a search.)
        if agentsPage == .library, !librarySearch.isEmpty {
            librarySearch = ""
            return true
        }
        if agentsPage == .recipes, recipeOpen != nil {
            closeRecipe()
            return true
        }
        return false
    }

    // MARK: Recipes

    /// Jobs you hand out often, saved to run again (set by the app).
    var recipesStore: RecipesStore?
    /// The recipe that's open on the Recipes page; nil shows them all.
    @Published var recipeOpen: UUID?
    /// What's been typed into the open recipe's blanks, by each blank's key.
    @Published var recipeBlanks: [String: String] = [:]
    /// What became of the last run added from a recipe: "Added to Biology: …".
    @Published var recipeNote: String?

    /// The Recipes page of the agent room: back at the recipe you had open, or the list.
    /// (Clicked again while it's showing, it goes back to the list.)
    func openRecipes() {
        let already = tool == .agents && agentsPage == .recipes
        tool = .agents
        agentsPage = .recipes
        if already || recipesStore?.book.recipe(recipeOpen) == nil {
            closeRecipe()
        }
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Opens a recipe, to fill in its blanks and run it, or to change it.
    func showRecipe(_ id: UUID) {
        guard recipesStore?.book.recipe(id) != nil else { return }
        tool = .agents
        agentsPage = .recipes
        if recipeOpen != id {
            recipeOpen = id
            recipeBlanks = [:]
            recipeNote = nil
        }
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Back to the list. A recipe that was started and never written is dropped.
    func closeRecipe() {
        recipeOpen = nil
        recipeBlanks = [:]
        recipeNote = nil
        recipesStore?.change { $0.tidy() }
    }

    /// A new, empty recipe, opened to be written.
    func newRecipe() {
        guard let store = recipesStore else { return }
        var made: Recipe?
        store.change { made = $0.addEmpty() }
        if let made = made {
            showRecipe(made.id)
        }
    }

    /// Saves a job as a recipe and opens it, to name it and mark its blanks. False if
    /// there was no job to save.
    @discardableResult
    func saveRecipe(job: String, chain: Bool, name: String = "") -> Bool {
        guard let store = recipesStore else { return false }
        var saved: Recipe?
        store.change { saved = $0.add(name: name, text: job, chain: chain) }
        guard let recipe = saved else { return false }
        showRecipe(recipe.id)
        return true
    }

    /// The job in the box becomes a recipe (and leaves the box).
    func saveDraftAsRecipe() {
        if saveRecipe(job: agentDraft, chain: agentDraftChain) {
            agentDraft = ""
            agentDraftChain = false
        }
    }

    /// An agent's job becomes a recipe: one for a chain, if a chain did it.
    func saveRecipe(from agent: UUID) {
        guard let job = agentsStore?.team.job(agent), Recipe.canSave(job) else { return }
        saveRecipe(job: job.task, chain: job.chain != nil, name: Recipe.name(from: job))
    }

    func changeRecipe(_ id: UUID, _ edit: (inout Recipe) -> Void) {
        recipesStore?.change { $0.change(id, edit) }
    }

    func removeRecipe(_ id: UUID) {
        recipesStore?.change { $0.remove(id) }
        if recipeOpen == id {
            closeRecipe()
        }
    }

    /// Runs a recipe: an agent (or a chain) starts on its job, with what's typed in its
    /// blanks. If a blank is still empty, the recipe opens to be filled in instead, and
    /// this returns false.
    @discardableResult
    func runRecipe(_ id: UUID) -> Bool {
        guard let recipe = recipesStore?.book.recipe(id) else { return false }
        let values = recipeOpen == id ? recipeBlanks : [:]
        guard recipe.isReady(with: values) else {
            showRecipe(id)
            return false
        }
        let job = recipe.job(with: values)
        let started = recipe.chain ? startChain(goal: job, title: recipe.chainTitle(with: values))
                                   : startAgent(task: job, name: recipe.agentName(with: values))
        guard started else { return false }
        recipesStore?.change { $0.used(id) }
        recipeNote = nil
        if recipeOpen == id {
            recipeBlanks = [:]
        }
        return true
    }

    /// Adds a run of a recipe to the group that's showing without starting it: it waits
    /// there for Start, like a task typed in the box. You stay on the recipe, its blanks
    /// emptied, so that several runs can be lined up one after another. If a blank is
    /// still empty, the recipe opens to be filled in instead, and this returns false.
    @discardableResult
    func queueRecipe(_ id: UUID) -> Bool {
        guard let recipe = recipesStore?.book.recipe(id) else { return false }
        let values = recipeOpen == id ? recipeBlanks : [:]
        guard recipe.isReady(with: values) else {
            showRecipe(id)
            return false
        }
        guard let store = agentsStore else { return false }
        let job = recipe.job(with: values)
        let group = store.team.group(agentGroupOpen)?.id
        var added: AgentJob?
        store.change { team in
            if recipe.chain {
                added = team.addChain(title: recipe.chainTitle(with: values), goal: job, kind: .write, group: group, start: false)
            } else {
                added = team.add(name: recipe.agentName(with: values), task: job, group: group, start: false)
            }
        }
        guard let task = added else { return false }
        agentGroupOpen = group
        agentOpen = task.id
        agentShowsWork = false
        recipesStore?.change { $0.used(id) }
        recipeNote = "Added to \(store.team.groupName(group)): \(task.name). It waits there until you press Start."
        if recipeOpen == id {
            recipeBlanks = [:]
        }
        return true
    }

    // MARK: The report library

    /// Every report your agents have finished, kept to find again (set by the app).
    var reportsStore: ReportsStore?
    /// The report that's open in the library; nil shows the list.
    @Published var reportOpen: UUID?
    /// Which part of it is showing (a chain's has one for each stage); nil is its last.
    @Published var reportPart: UUID?
    /// What's typed in the library's search box, and the subject picked ("" for all).
    @Published var librarySearch = ""
    @Published var librarySubject = ""
    /// Shows the folder kept with a report, or opens a file in it (set by the app).
    var onShowReportFolder: ((String) -> Void)?
    var onOpenReportFile: ((String, String) -> Void)?

    /// The Library page of the agent room: back at the report you had open, or the list.
    /// (Clicked again while it's showing, it goes back to the list.)
    func openLibrary() {
        let already = tool == .agents && agentsPage == .library
        tool = .agents
        agentsPage = .library
        // Reports pinned to an assignment that's since been deleted are pinned to nothing.
        if let known = assignmentsStore?.assignments.items.map({ $0.id }) {
            reportsStore?.change { $0.keepPins(to: Set(known)) }
        }
        if already || reportsStore?.library.report(reportOpen) == nil {
            closeReport()
        }
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Opens a report in the library, at one of its parts if it's a chain's.
    func showReport(_ id: UUID, part: UUID? = nil) {
        guard reportsStore?.library.report(id) != nil else { return }
        tool = .agents
        agentsPage = .library
        reportOpen = id
        reportPart = part
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    func closeReport() {
        reportOpen = nil
        reportPart = nil
    }

    func removeReport(_ id: UUID) {
        reportsStore?.change { $0.remove(id) }
        if reportOpen == id {
            closeReport()
        }
    }

    func renameReport(_ id: UUID, to title: String) {
        reportsStore?.change { $0.rename(id, to: title) }
    }

    /// Pins a report to a subject. Picking the subject it's already pinned to unpins it.
    func pinReport(_ id: UUID, subject: String) {
        guard let report = reportsStore?.library.report(id) else { return }
        let same = !report.subject.isEmpty && ReportLibrary.same(report.subject, subject)
        reportsStore?.change { $0.pin(id, subject: same ? "" : subject) }
    }

    /// Pins a report to an assignment, where it then shows. Picking the one it's already
    /// pinned to unpins it.
    func pinReport(_ id: UUID, assignment: UUID) {
        guard let report = reportsStore?.library.report(id) else { return }
        if report.assignment == assignment {
            reportsStore?.change { $0.pin(id, assignment: nil) }
        } else {
            let subject = assignmentsStore?.assignments.item(assignment)?.subject ?? ""
            reportsStore?.change { $0.pin(id, assignment: assignment, subject: subject) }
        }
    }

    // MARK: Assignments and marks

    /// Your assignments and results, shared by every screen (set by the app).
    var assignmentsStore: AssignmentsStore?

    /// The two halves of Assignments.
    enum AssignmentsTab: Equatable {
        case work
        case marks
    }

    @Published var assignmentsTab = AssignmentsTab.work

    /// The assignment (or result) open at the side.
    @Published var assignmentOpen: UUID? {
        didSet {
            // Finished with one: tidy what was typed, and drop it if it never got a name.
            guard let before = oldValue, before != assignmentOpen else { return }
            assignmentsStore?.change { all in
                if all.item(before)?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    all.remove(before)
                }
                all.tidy()
            }
            // Closing a result leaves Marks on its subject.
            if assignmentOpen == nil, assignmentsTab == .marks, let item = assignmentsStore?.assignments.item(before) {
                marksSubject = item.subject
            }
        }
    }

    /// The subject showing in Marks, as you wrote it; nil for the first one.
    @Published var marksSubject: String?

    /// The assignment the assistant is breaking into steps right now.
    @Published var planningAssignment: UUID?
    /// What went wrong the last time it tried, or what it used instead.
    @Published var planningNote: String?
    /// Asks the app to have the assistant break an assignment into steps (set by the app).
    var onPlanAssignment: ((UUID) -> Void)?

    func openAssignments() {
        tool = .assignments
        level = .lanes
    }

    // MARK: A task sheet

    /// The file being read as a task sheet ("Macbeth task.pdf"), while it's being read.
    @Published var sheetReading: String?
    /// How reading the last sheet went, if there's something to say.
    @Published var sheetNote: String?
    /// Set by the app: reads a file as a task sheet, or lets you pick one first.
    var onReadAssignmentSheet: ((URL) -> Void)?
    var onPickAssignmentSheet: (() -> Void)?

    /// A file dropped on Assignments (or picked): the app reads it and the assistant
    /// fills in a new assignment from it. False if it isn't a kind that can be read.
    @discardableResult
    func readAssignmentSheet(_ url: URL) -> Bool {
        tool = .assignments
        assignmentsTab = .work
        if level == .rest || level == .peek {
            level = .lanes
        }
        guard AssignmentSheet.canRead(url.lastPathComponent) else {
            sheetNote = AssignmentSheet.cantRead
            return false
        }
        guard sheetReading == nil, let read = onReadAssignmentSheet else { return false }
        sheetNote = nil
        sheetReading = url.lastPathComponent
        read(url)
        return true
    }

    /// The sheet has been read: the new assignment opens to be checked.
    func finishSheet(_ item: UUID?, note: String?) {
        sheetReading = nil
        sheetNote = note
        if let item = item, tool == .assignments {
            showAssignment(item)
        }
    }

    func expandAssignments() {
        tool = .assignments
        level = .detail
    }

    /// Opens an assignment at the side; click it again to close it.
    func showAssignment(_ id: UUID, toggle: Bool = false) {
        tool = .assignments
        if assignmentsStore?.assignments.item(id)?.kind == .result {
            assignmentsTab = .marks
        } else {
            assignmentsTab = .work
        }
        assignmentOpen = toggle && assignmentOpen == id ? nil : id
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// A new assignment due a week from today, opened for you to fill in.
    func newAssignment(now: Date = Date(), calendar: Calendar = .current) {
        guard let store = assignmentsStore else { return }
        let due = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        let item = Assignment(title: "", due: due)
        store.change { $0.add(item) }
        showAssignment(item.id)
    }

    /// A result to record: a test or exam you've sat. Given an exam from the planner, it
    /// takes the exam's name, subject and date.
    func newResult(subject: String = "", exam: Exam? = nil, now: Date = Date(), calendar: Calendar = .current) {
        guard let store = assignmentsStore else { return }
        var item = Assignment(title: exam?.title ?? "", subject: exam?.subject ?? subject,
                              due: exam?.date ?? calendar.startOfDay(for: now), kind: .result)
        item.examID = exam?.id
        item.handedIn = true
        store.change { $0.add(item) }
        marksSubject = item.subject
        showAssignment(item.id)
    }

    /// Breaks an assignment into steps: the assistant plans it if it's set up, and the
    /// usual steps for that kind of work go in if not.
    func planAssignment(_ id: UUID) {
        guard planningAssignment == nil, let item = assignmentsStore?.assignments.item(id) else { return }
        planningNote = nil
        if let ask = onPlanAssignment {
            planningAssignment = id
            ask(id)
        } else {
            assignmentsStore?.change { $0.plan(id, with: AssignmentBreakdown.standard(for: item.title)) }
        }
    }

    /// The assistant's plan came back (or didn't): the steps go in, or the usual ones do,
    /// with a note saying why.
    func finishPlanning(_ id: UUID, steps: [AssignmentStep]?, problem: String?) {
        // Only the screen that asked puts the plan in (the assignments are shared).
        guard planningAssignment == id else { return }
        planningAssignment = nil
        guard let item = assignmentsStore?.assignments.item(id) else { return }
        if let steps = steps, !steps.isEmpty {
            assignmentsStore?.change { $0.plan(id, with: steps) }
            planningNote = nil
        } else {
            assignmentsStore?.change { $0.plan(id, with: AssignmentBreakdown.standard(for: item.title)) }
            planningNote = (problem ?? "The assistant couldn't plan this one.") + " These are the usual steps for this kind of work: change them to suit."
        }
    }

    /// Homework and the steps of assignments still to do: everything the study plan fits in.
    var studyTasks: [PlannerTask] {
        (plannerStore?.planner.tasks ?? []) + (assignmentsStore?.assignments.planTasks() ?? [])
    }

    /// Opens what a planned study session is for: homework in the planner, or the assignment
    /// a step belongs to.
    func openPlanned(_ id: UUID) {
        if plannerStore?.planner.task(id) != nil {
            editTask(id)
        } else if let owner = assignmentsStore?.assignments.owner(of: id) {
            showAssignment(owner.id)
        }
    }

    // MARK: Bookmarks

    /// Your bookmarks, shared by every screen (set by the app).
    var bookmarksStore: BookmarksStore?

    /// The bookmark being edited in the side panel.
    @Published var bookmarkEdit: UUID? {
        didSet {
            // Finished with one: a name left blank becomes its site.
            if let before = oldValue, before != bookmarkEdit {
                bookmarksStore?.tidy(before)
            }
        }
    }

    /// The group whose bookmarks are showing; nil for all of them.
    @Published var bookmarkGroup: String?

    func openBookmarks() {
        tool = .bookmarks
        bookmarkEdit = nil
        if let group = bookmarkGroup, bookmarksStore?.bookmarks(in: group).isEmpty != false {
            bookmarkGroup = nil
        }
        level = .lanes
    }

    /// Opens a bookmark in your browser. Only web pages open.
    func openBookmark(_ bookmark: Bookmark) {
        guard let address = BookmarkText.address(from: bookmark.url), let url = URL(string: address) else { return }
        onOpenURL?(url)
    }

    /// Adds what was typed or dropped: a link, or a name and a link. It goes in the group
    /// that's showing. Returns false if there's no link in it.
    @discardableResult
    func addBookmark(typed: String) -> Bool {
        guard let store = bookmarksStore else { return false }
        return store.add(typed: typed, group: bookmarkGroup ?? "") != nil
    }

    /// Click a bookmark's pencil to edit it; click it again to stop.
    func editBookmark(_ id: UUID) {
        tool = .bookmarks
        bookmarkEdit = bookmarkEdit == id ? nil : id
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    func removeBookmark(_ id: UUID) {
        if bookmarkEdit == id {
            bookmarkEdit = nil
        }
        bookmarksStore?.remove(id)
        if let group = bookmarkGroup, bookmarksStore?.bookmarks(in: group).isEmpty != false {
            bookmarkGroup = nil
        }
    }

    /// The panel's black outline at a level: its size plus the curved shoulders.
    func outline(_ level: NotchLevel) -> CGSize {
        let body = size(level)
        return CGSize(width: body.width + metrics.shoulder(level, ears: restEars) * 2, height: body.height)
    }

    func resize(_ level: NotchLevel, to size: CGSize) {
        guard level != .rest else { return }
        customSizes[level] = metrics.clamp(size, for: level)
    }

    func finishResizing() {
        onResized?(customSizes)
    }

    /// Back to the standard size (double-click the corner grip).
    func resetSize(_ level: NotchLevel) {
        customSizes[level] = nil
        onResized?(customSizes)
    }

    /// Every panel back to its standard size (Settings → General).
    func resetAllSizes() {
        customSizes = [:]
        onResized?(customSizes)
    }

    /// Settings, in the notch: a section per topic down the left.
    func openSettings(_ section: SettingsSection? = nil) {
        if let section = section {
            settingsSection = section
        }
        tool = .settings
        level = .lanes
    }

    func openNotes() {
        tool = .notes
        if selectedNoteID == nil || notesStore?.note(selectedNoteID) == nil {
            selectedNoteID = notesStore?.notes.first?.id
        }
        level = .lanes
    }

    /// The timetable, showing this week, in the bigger panel (a whole day, extracurriculars
    /// included, needs the room).
    func openTimetable() {
        tool = .timetable
        timetableWeek = timetableStore?.timetable.week(of: Date()) ?? 0
        timetableEdit = nil
        level = .detail
    }

    func expandTimetable() {
        tool = .timetable
        level = .detail
    }

    /// Click a lesson (or an empty slot) to edit it; click it again to stop.
    func editLesson(day: Int, period: UUID) {
        let slot = Timetable.Slot(week: timetableWeek, day: day, period: period)
        timetableEdit = timetableEdit == .lesson(slot) ? nil : .lesson(slot)
    }

    func editPeriod(_ id: UUID) {
        timetableEdit = timetableEdit == .period(id) ? nil : .period(id)
    }

    /// A new period after the last one, opened for editing.
    func addPeriod() {
        guard let store = timetableStore else { return }
        var added: UUID?
        store.change { added = $0.addPeriod() }
        if let id = added {
            timetableEdit = .period(id)
        }
    }

    // MARK: The tour

    /// Which page of the tour is showing.
    @Published var tourPage = 0
    /// The tour hasn't been finished or skipped yet: the primary menu offers it.
    @Published var tourPending = false
    /// You left the tour to try something: every tool shows a way back to it.
    @Published var tourPaused = false
    /// The tour was finished or skipped (the app remembers, for every screen).
    var onTourFinished: (() -> Void)?

    /// Opens the tour where you left it, or from the start.
    func openTour(fromStart: Bool = false) {
        if fromStart || tourPage >= Tour.pageCount {
            tourPage = 0
        }
        tourPaused = false
        tool = .tour
        level = .detail
    }

    /// The next page; after the last one, the tour is finished.
    func tourNext() {
        if tourPage >= Tour.pageCount - 1 {
            finishTour()
        } else {
            tourPage += 1
        }
    }

    func tourBack() {
        tourPage = max(0, tourPage - 1)
    }

    /// Finished or skipped: it isn't offered again (Settings → General can still show it),
    /// and you land on the primary menu.
    func finishTour() {
        tourPage = 0
        tourPaused = false
        tourPending = false
        onTourFinished?()
        tool = .mail
        goHome()
    }

    /// A page's button: go and look at the real thing. The tour waits, and each tool shows
    /// a way back to it.
    func tryFromTour(_ target: TourPage.Target) {
        switch target {
        case .mail: openLanes()
        case .planner: openPlanner()
        case .timetable: openTimetable()
        case .notes: openNotes()
        case .assistant: openAssistant()
        case .extras: openExtras()
        case .bookmarks: openBookmarks()
        case .assignments: openAssignments()
        case .agents: openAgents()
        case .settings(let section): openSettings(section)
        }
        tourPaused = true
    }

    /// The Mac extras: the shelf, clipboard history, the focus timer, now playing.
    func openExtras() {
        tool = .extras
        level = .lanes
    }

    func expandExtras() {
        tool = .extras
        level = .detail
    }

    // MARK: Planner

    /// Homework and exams.
    func openPlanner() {
        tool = .planner
        plannerEdit = nil
        level = .lanes
    }

    func expandPlanner() {
        tool = .planner
        level = .detail
    }

    /// Click homework to edit it; click it again to stop.
    func editTask(_ id: UUID) {
        tool = .planner
        plannerEdit = plannerEdit == .task(id) ? nil : .task(id)
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    func editExam(_ id: UUID) {
        tool = .planner
        plannerEdit = plannerEdit == .exam(id) ? nil : .exam(id)
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Adds homework from one typed line ("Maths worksheet fri 4pm 45m"). A subject from the
    /// timetable named in it becomes its subject. Returns false if nothing was typed.
    @discardableResult
    func addTask(typed: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let store = plannerStore else { return false }
        let entry = QuickEntry.parse(typed, now: now, calendar: calendar)
        guard !entry.title.isEmpty else { return false }
        var task = PlannerTask(title: entry.title, due: entry.due, hasTime: entry.hasTime)
        task.minutes = entry.minutes ?? PlannerTask.guessMinutes(for: entry.title)
        task.subject = Planner.subject(in: entry.title, among: timetableStore?.timetable.classes ?? []) ?? ""
        store.change { $0.add(task) }
        return true
    }

    /// A new exam a week from today, opened for editing.
    func newExam(now: Date = Date(), calendar: Calendar = .current) {
        guard let store = plannerStore else { return }
        let date = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        let exam = Exam(title: "", date: date)
        store.change { $0.add(exam) }
        tool = .planner
        plannerEdit = .exam(exam.id)
        if level == .rest || level == .peek {
            level = .lanes
        }
    }

    /// Closes the planner's side panel.
    func closePlannerEdit() {
        plannerEdit = nil
    }

    private func removeIfUnnamed(_ edit: PlannerEdit) {
        plannerStore?.change { planner in
            switch edit {
            case .task(let id):
                if planner.task(id)?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    planner.removeTask(id)
                }
            case .exam(let id):
                if planner.exam(id)?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    planner.removeExam(id)
                }
            }
        }
    }

    /// Opens the email homework or an exam came from, in the notch.
    func openEmail(_ id: String) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        open(accountID: message.accountID, messageID: id)
    }

    /// Whether the notch still has an email (to offer "Open email").
    func hasEmail(_ id: String?) -> Bool {
        guard let id = id else { return false }
        return messages.contains { $0.id == id }
    }

    /// The assistant (Claude or Qwen).
    func openAssistant() {
        tool = .assistant
        level = .lanes
    }

    func expandAssistant() {
        tool = .assistant
        level = .detail
    }

    /// Notes in the bigger, detail-sized panel.
    func expandNotes() {
        tool = .notes
        level = .detail
    }

    func newNote() {
        guard let store = notesStore else { return }
        store.removeEmpty(except: nil)
        selectedNoteID = store.add().id
        if tool != .notes || level == .rest || level == .peek {
            tool = .notes
            level = .lanes
        }
    }

    func selectNote(_ id: UUID) {
        notesStore?.removeEmpty(except: id)
        selectedNoteID = id
    }

    /// The phone plugged into the Mac by cable ("iPhone"), if any: a red dot beside the notch.
    @Published var phoneConnected: String?
    /// Its battery ("87%"), when that's known.
    @Published var phoneBattery: String?

    /// Width of each ear beside the closed notch: wide enough for every unread count, and
    /// for the red phone dot.
    var restEars: CGFloat {
        guard !minimised else { return 0 }
        var width = NotchMetrics.earWidth(for: accounts.map { unreadCount($0.id) })
        if phoneConnected != nil {
            width = max(width, NotchMetrics.dotEarWidth)
        }
        if focusRunning {
            // The timer's minutes, and the phone's dot beside them if there is one.
            width = max(width, NotchMetrics.focusEarWidth + (phoneConnected == nil ? 0 : 14))
        }
        if levelHUD != nil {
            width = max(width, NotchMetrics.levelEarWidth)
        } else if !steadyLevels.isEmpty {
            // A small gauge at the edge of each ear, beside whatever else is there.
            width = (width > 0 ? width : NotchMetrics.steadyLevelPad) + NotchMetrics.steadyLevelWidth
        }
        return width
    }

    // MARK: Volume and brightness

    /// The volume or brightness, shown beside the closed notch for a moment after it changes.
    @Published var levelHUD: LevelReading?
    /// The volume and brightness as they are, when they're kept beside the closed notch
    /// all the time (Settings → Extras). Empty when they aren't.
    @Published var steadyLevels: [LevelReading] = []

    func steadyLevel(_ kind: LevelKind) -> LevelReading? {
        steadyLevels.first { $0.kind == kind }
    }

    // MARK: Typing into your documents

    /// The app your cursor was in when the notch opened ("Pages"), where "Type into Pages" types.
    @Published var typingTarget: String?
    /// How the last go at typing, or at reading a selection, went: shown in the chat.
    @Published var typingNote: String?
    /// Set by the app: types text where your cursor is, reads what's selected there, or
    /// takes what you've copied.
    var onTypeIntoDocument: ((String) -> Void)?
    var onUseSelection: (() -> Void)?
    var onUseClipboard: (() -> Void)?

    /// Types an answer into the document you were in, as plain text.
    func typeIntoDocument(_ answer: String) {
        let text = DocumentText.forTyping(answer)
        guard !text.isEmpty else { return }
        typingNote = nil
        onTypeIntoDocument?(text)
    }

    func useSelection() {
        typingNote = nil
        onUseSelection?()
    }

    func useClipboard() {
        typingNote = nil
        onUseClipboard?()
    }

    func account(_ id: String) -> MailAccount? {
        accounts.first { $0.id == id }
    }

    var activeAccount: MailAccount? { account(activeAccountID) }

    var openMessage: MailMessage? {
        guard let id = openMessageID else { return nil }
        return messages.first { $0.id == id }
    }

    /// The account a reply goes out from: the inbox the mail arrived in, unless you pick another.
    var replyFrom: MailAccount? { account(replyFromID ?? activeAccountID) }

    /// What the hover tiles show: the newest unread message, or else the newest message.
    func headline(_ accountID: String) -> MailMessage? {
        let list = inbox(accountID)
        return list.first { $0.isUnread } ?? list.first
    }

    // MARK: Moving between levels

    /// The primary menu (tools, starting with Mail). Shown by hovering, it closes when the
    /// pointer leaves; opened with a click, it stays until you click somewhere else.
    @Published var homePinned = false

    func peek() {
        if level == .rest {
            homePinned = false
            level = .peek
        }
    }

    func unpeek() {
        if level == .peek && !homePinned { level = .rest }
    }

    /// Opens the primary menu and keeps it open.
    func goHome() {
        homePinned = true
        level = .peek
        // Leaving the tour this way keeps your page; the primary menu offers it again.
        if tool == .tour {
            tool = .mail
        }
    }

    /// A click on the hover menu keeps it open.
    func pinHome() {
        if level == .peek { homePinned = true }
    }

    func openLanes() {
        tool = .mail
        level = .lanes
    }

    func back() {
        level = .lanes
    }

    func close() {
        level = .rest
        recordingKey = nil
        sentFrom = nil
        homePinned = false
        endSearch()
        notesStore?.removeEmpty(except: nil)
        timetableEdit = nil
        closePlannerEdit()
        bookmarkEdit = nil
        assignmentOpen = nil
        // A tour left open, or left to try something, waits on the primary menu.
        tourPaused = false
        if tool == .tour {
            tool = .mail
        }
    }

    /// Expand one inbox, opening the given message (or the newest).
    func open(accountID: String, messageID: String? = nil) {
        tool = .mail
        let target = messageID ?? inbox(accountID).first?.id
        activeAccountID = accountID
        openMessageID = target
        replyFromID = nil
        replyText = ""
        sentFrom = nil
        // Opening an email marks it read: sample mail here, real mail in the app's own tally.
        if canAct, let target = target {
            setSampleRead(target, true)
        }
        if !canAct, let target = target {
            onOpenMessage?(target)
        }
        level = .detail
    }

    func open(accountAt index: Int) {
        guard accounts.indices.contains(index) else { return }
        open(accountID: accounts[index].id)
    }

    // MARK: Message actions

    /// Archive the open message and move on to the next one in the same inbox.
    func archiveOpen() {
        guard canAct, let id = openMessageID else { return }
        let before = inbox(activeAccountID)
        guard let index = before.firstIndex(where: { $0.id == id }) else { return }

        messages.removeAll { $0.id == id }

        let after = inbox(activeAccountID)
        let next: MailMessage? = after.isEmpty ? nil : after[min(index, after.count - 1)]
        openMessageID = next?.id
        if let next = next {
            setSampleRead(next.id, true)
        }
        replyFromID = nil
        replyText = ""
        sentFrom = nil
    }

    func markOpenUnread() {
        guard let id = openMessageID else { return }
        setRead(id, read: false)
    }

    /// Marks one email read or unread, in the notch.
    func setRead(_ id: String, read: Bool) {
        if canAct {
            setSampleRead(id, read)
        } else {
            onSetRead?(id, read)
        }
    }

    func toggleRead(_ id: String) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        setRead(id, read: message.isUnread)
    }

    /// Marks a whole inbox read or unread, in the notch.
    func markAll(_ accountID: String, read: Bool) {
        guard canAct else {
            onMarkAll?(accountID, read)
            return
        }
        var changed = messages
        for index in changed.indices where changed[index].accountID == accountID {
            changed[index].isUnread = !read
        }
        messages = changed
    }

    func undoMarkAll() {
        onUndoMarkAll?()
    }

    func chooseReplyAccount(_ id: String) {
        replyFromID = id
    }

    func send() {
        guard canAct, openMessage != nil else { return }
        // Sample data: nothing leaves the Mac. Real replies happen in Gmail.
        sentFrom = replyFrom?.name ?? "your account"
        replyText = ""
    }

    func installUpdate() {
        onInstallUpdate?()
    }


    // MARK: Gmail in the browser

    /// Opens a web page that belongs with one of your inboxes (a link in one of its emails,
    /// or its Gmail), in the browser profile that inbox is signed in to. Set by the app.
    var onOpenAccountURL: ((URL, String) -> Void)?

    /// Opens a page for an inbox. Without one, a Gmail link still says whose it is; any
    /// other page opens the way links always have.
    func open(_ url: URL, for accountID: String?) {
        let id = accountID ?? self.accountID(inGmailLink: url)
        if let id = id, let email = account(id)?.email, !email.isEmpty, let open = onOpenAccountURL {
            open(url, email)
        } else {
            onOpenURL?(url)
        }
    }

    /// The inbox a Gmail link is for: the one whose address it carries.
    func accountID(inGmailLink url: URL) -> String? {
        guard url.host?.lowercased() == "mail.google.com",
              let user = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "authuser" })?.value,
              !user.isEmpty else { return nil }
        return accounts.first { account in
            account.email.map { BrowserProfiles.same($0, user) } ?? false
        }?.id
    }

    /// Opens a planner task's link (its page in Classroom, or its email in Gmail) where
    /// the inbox its email came to is signed in.
    func openTaskLink(_ link: URL, emailID: String?) {
        let from = emailID.flatMap { id in messages.first { $0.id == id }?.accountID }
        open(link, for: from)
    }

    func openInGmail() {
        if let message = openMessage, let link = message.link {
            open(link, for: message.accountID)
        } else {
            openAccountInGmail(activeAccountID)
        }
    }

    func openAccountInGmail(_ accountID: String) {
        if let url = gmailURL(for: accountID) {
            open(url, for: accountID)
        }
    }

    /// New message in Gmail, from the inbox that's open (or the first account).
    func composeInGmail() {
        let accountID = level == .detail ? activeAccountID : (accounts.first?.id ?? activeAccountID)
        let compose = [URLQueryItem(name: "view", value: "cm"),
                       URLQueryItem(name: "fs", value: "1"),
                       URLQueryItem(name: "tf", value: "1")]
        if let url = gmailURL(for: accountID, extra: compose) {
            open(url, for: accountID)
        }
    }

    /// A link clicked inside an email. Web links open in the browser, in the profile the
    /// email's inbox is signed in to; email addresses start a new message in Gmail from
    /// the inbox that's open.
    func openLink(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "http", "https":
            open(url, for: openMessage?.accountID)
        case "mailto":
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var compose = [URLQueryItem(name: "view", value: "cm"),
                           URLQueryItem(name: "fs", value: "1"),
                           URLQueryItem(name: "tf", value: "1")]
            if let to = parts?.path, !to.isEmpty {
                compose.append(URLQueryItem(name: "to", value: to))
            }
            for item in parts?.queryItems ?? [] {
                switch item.name.lowercased() {
                case "subject":
                    compose.append(URLQueryItem(name: "su", value: item.value))
                case "body", "cc", "bcc":
                    compose.append(URLQueryItem(name: item.name.lowercased(), value: item.value))
                default:
                    break
                }
            }
            if let link = gmailURL(for: activeAccountID, extra: compose) {
                open(link, for: activeAccountID)
            }
        default:
            break
        }
    }

    /// The line under an email that's still Gmail's short preview.
    func previewNote(for message: MailMessage) -> String {
        if message.couldNotLoad {
            return "Gmail didn't hand over the whole email. Open it in Gmail to read it all."
        }
        switch wholeEmails {
        case .coming:
            return "This is Gmail's preview. The whole email shows here in a moment."
        case .whenOpened:
            return "This is Gmail's preview. The whole email shows here within a minute."
        case .addOnNeedsReload:
            return "This is Gmail's preview. To see whole emails, reload Notch Inbox Link on chrome://extensions, or quit and reopen Chrome."
        }
    }

    func gmailURL(for accountID: String, extra: [URLQueryItem] = []) -> URL? {
        guard let email = account(accountID)?.email else { return nil }
        var components = URLComponents(string: "https://mail.google.com/mail/u/")
        components?.queryItems = [URLQueryItem(name: "authuser", value: email)] + extra
        return components?.url
    }

    private func setSampleRead(_ id: String, _ read: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }), messages[index].isUnread == read else { return }
        messages[index].isUnread = !read
    }
}
