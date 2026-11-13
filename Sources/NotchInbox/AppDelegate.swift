import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Menu-bar-only app: no Dock icon and no app menu. A notch panel per screen is created
    /// at launch. Settings (Gmail link, accounts, assistant, updates, Quit) open inside the
    /// notch from the gear button; the envelope in the menu bar has a short menu too.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private static let accountOrderKey = "linkedAccountOrder"
    /// Choices you made in Settings. (Version 2: build 5's automatic guesses are dropped.)
    private static let inboxChoicesKey = "inboxChoices.v2"
    private static let hiddenAccountsKey = "hiddenAccounts"
    /// Every account the app has met. One it hasn't met before starts out of the notch
    /// (unless it's the very first), so the notch starts with one inbox and you add the rest.
    private static let metAccountsKey = "accountsMet"
    private var metAccounts: Set<String> = []

    /// One notch per connected screen, keyed by display.
    private var screens: [CGDirectDisplayID: NotchWindowController] = [:]
    private var levelWatchers: [CGDirectDisplayID: AnyCancellable] = [:]
    private var screenObserver: NSObjectProtocol?

    private let updater = Updater()
    private let browserLink = BrowserLink()
    private var mailbox = LiveMailbox(order: UserDefaults.standard.stringArray(forKey: AppDelegate.accountOrderKey) ?? [])
    private var lastFeedAt: Date?
    private var wholeEmails: NotchModel.WholeEmails = .coming
    /// The latest feeds, so changing what an account shows takes effect at once.
    private var lastFeeds: [AccountFeeds] = []
    /// Per account, as you chose in the menu: the Primary tab (plus Google mail) or the whole inbox.
    private var inboxChoices: [String: InboxChoice] = [:]
    /// What each account's mail in the mailbox came from, to start it afresh when that changes.
    private var appliedViews: [String: InboxChoice] = [:]
    /// The add-on's latest upload, for Copy Debug Info.
    private var lastUpload: FeedUpload?
    /// The mailbox as last written to disk: its revision, and what each account was showing.
    private var savedRevision = -1
    private var savedViews: [String: InboxChoice] = [:]
    private var saveMailboxWork: DispatchWorkItem?
    /// The mailbox file is written here, off the main thread: it can hold thousands of emails.
    private let saveQueue = DispatchQueue(label: "NotchInbox.SaveMailbox", qos: .utility)
    /// Whole emails, one file each, so old mail still opens in full.
    private let emailFiles = WholeEmailStore()
    /// Whole emails are tidied to the limit once the add-on has been heard from.
    private var tidiedEmailFiles = false

    private var statusItem: NSStatusItem?
    /// The envelope's short menu (Open, Settings, Quit), also on the mail tab's right-click.
    private var appMenu: NSMenu?
    /// What Settings shows, and what its buttons do.
    private let settings = AppSettings.shared

    /// Minimised: a small tab with a mail icon, slid anywhere along the top, stands in for the notch.
    private static let minimisedKey = "minimisedToIcon"
    private var minimised = UserDefaults.standard.bool(forKey: AppDelegate.minimisedKey)
    private let mailIcon = MailIconController()
    /// Notes, shared by every screen's notch.
    private let notes = NotesStore()
    /// The timetable, shared by every screen's notch.
    private let timetable = TimetableStore()
    /// Files parked on the shelf, shared by every screen's notch.
    private let shelf = ShelfStore()
    private let bookmarks = BookmarksStore()
    private let assignments = AssignmentsStore()
    /// Your agents and their jobs, shared by every screen's notch.
    private let agents = AgentsStore()
    private lazy var agentRunner = AgentRunner(store: agents, assistant: Assistant.shared, settings: settings)
    /// Jobs saved to run again, and every report the agents have finished.
    private let recipes = RecipesStore()
    private let reports = ReportsStore()
    /// The team chat agents share with the chief of staff and you.
    private let team = TeamStore()
    private lazy var teamDesk = TeamDesk(store: team, agents: agents, assistant: Assistant.shared, settings: settings)
    /// Types into the document you're in, and reads what's selected there.
    private let documentTyper = DocumentTyper()
    /// The volume and brightness keys, when the notch has taken them over.
    private let mediaKeys = MediaKeyTap()
    private var historyAskedAt: Date?
    private var historyAdded = 0
    private var historyHeardFrom: Set<String> = []
    private var levelHide: DispatchWorkItem?
    private var accessibilityCheck: DispatchWorkItem?
    private var accessibilityChecksLeft = 0
    /// Homework and exams, shared by every screen's notch.
    private let planner = PlannerStore()
    /// Reads mail into the planner: Classroom's emails here, others with the assistant if that's on.
    private lazy var plannerMail = PlannerMailReader(store: planner, settings: settings, assistant: Assistant.shared)
    private var plannerMailWork: DispatchWorkItem?
    /// Sizes the open panel has been dragged to, by level.
    private static let panelSizesKey = "panelSizes"

    private var subscriptions = Set<AnyCancellable>()

    /// Set when you ask for an update check or install, so the notch can say how it went.
    private var userAskedForUpdate = false
    private var lastUpdaterState: Updater.State = .idle
    private var clearUpdateNote: DispatchWorkItem?

    private var models: [NotchModel] { screens.values.map { $0.model } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Claude Code runs as a separate program; if it quits before reading your question,
        // writing to it must fail quietly instead of ending this app.
        signal(SIGPIPE, SIG_IGN)
        endOtherCopies()
        restoreMailbox()
        connectSettings()
        installStatusItem()

        syncScreens()
        mailIcon.onOpen = { [weak self] in
            self?.openFromMailIcon()
        }
        Assistant.shared.context = { [weak self] in
            self?.assistantContext() ?? ""
        }
        Assistant.shared.timetableDescription = { [weak self] in
            guard let self = self else { return "" }
            return TimetableAgent.describe(self.timetable.timetable, now: Date())
        }
        Assistant.shared.applyTimetable = { [weak self] plan in
            guard let self = self else { return [] }
            var changes: [String] = []
            self.timetable.change { changes = TimetableAgent.apply(plan, to: &$0, now: Date()) }
            return changes
        }
        Assistant.shared.plannerDescription = { [weak self] in
            guard let self = self else { return "" }
            return PlannerAgent.describe(self.planner.planner, sessions: self.studyPlan(), now: Date())
        }
        Assistant.shared.applyPlanner = { [weak self] plan in
            guard let self = self else { return [] }
            var changes: [String] = []
            self.planner.change { changes = PlannerAgent.apply(plan, to: &$0, now: Date()) }
            return changes
        }
        Assistant.shared.onFindingChanged = { [weak self] in
            self?.readMailForPlannerSoon()
        }
        settings.onPlannerSettingsChanged = { [weak self] in
            self?.readMailForPlannerSoon()
        }
        connectAgents()
        connectLevels()
        connectTyping()
        planner.change { $0.tidy() }
        Assistant.shared.checkSetup()
        readMailForPlannerSoon()
        // The primary menu's tiles were rearranged: every screen follows.
        settings.onHomeMenuChanged = { [weak self] in
            self?.applyHomeMenu()
        }
        // The extras: what's playing, the focus timer, the clipboard, the shelf.
        settings.onExtrasChanged = { [weak self] in
            self?.applyExtras()
        }
        applyExtras()
        FocusTimer.shared.onFinished = { [weak self] session in
            self?.focusFinished(session)
        }
        FocusTimer.shared.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in self?.focusChanged(session) }
            .store(in: &subscriptions)
        // A red dot by the notch while a phone is plugged in by cable.
        PhoneCableWatcher.shared.$phone
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phone in self?.phoneChanged(phone) }
            .store(in: &subscriptions)
        PhoneCableWatcher.shared.$details
            .receive(on: DispatchQueue.main)
            .sink { [weak self] details in self?.phoneDetailsChanged(details) }
            .store(in: &subscriptions)
        PhoneCableWatcher.shared.start()
        mailIcon.menu = { [weak self] in
            self?.appMenu
        }
        if minimised {
            mailIcon.show()
            refreshMailIcon()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncScreens()
        }

        updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updaterChanged(state) }
            .store(in: &subscriptions)
        // Which build everyone is offered, for Settings → Updates.
        updater.$releasedBuild
            .receive(on: DispatchQueue.main)
            .sink { [weak self] build in
                guard let self = self, self.settings.releasedBuild != build else { return }
                self.settings.releasedBuild = build
            }
            .store(in: &subscriptions)
        updater.testBuilds = settings.testBuilds
        if updater.canInstall {
            updater.startChecking()
        }

        BrowserExtensionInstaller.refreshIfInstalled()
        browserLink.onFeeds = { [weak self] feeds, upload in
            self?.received(feeds, upload: upload) ?? LinkReply()
        }
        browserLink.onHistory = { [weak self] history in
            self?.receivedHistory(history)
        }
        settings.onFetchHistory = { [weak self] in
            self?.fetchHistory()
        }
        browserLink.onEmail = { [weak self] email in
            self?.received(email)
        }
        browserLink.start()
        offerTour()
    }

    // MARK: The tour

    /// The first time the app runs (or the first time after the update that brought the
    /// tour), the notch opens by itself and shows what everything does. It only ever opens
    /// by itself once; until it's finished or skipped, the primary menu keeps offering it.
    private func offerTour() {
        guard Tour.opensAtLaunch() else { return }
        // Give the notch a moment to settle in first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, Tour.opensAtLaunch(), let model = self.notchNearPointer(),
                  model.level == .rest || model.level == .peek else { return }
            Tour.markOffered()
            model.openTour(fromStart: true)
        }
    }

    private func tourFinished() {
        Tour.markSeen()
        for model in models where model.tourPending {
            model.tourPending = false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveMailboxNow(wait: true)
        emailFiles.finishWriting()
        notes.saveNow()
        timetable.saveNow()
        planner.saveNow()
        bookmarks.saveNow()
        assignments.saveNow()
        Assistant.shared.saveChats()
        Assistant.shared.usage.saveNow()
        // Agents still working are stopped: what they'd written so far is kept.
        agentRunner.stopAll()
        team.saveNow()
        recipes.saveNow()
        reports.saveNow()
        mediaKeys.stop()
        LevelsWatcher.shared.stop()
    }

    // MARK: Screens

    /// Keeps one notch panel on every connected screen as displays come and go.
    private func syncScreens() {
        let placements = NotchPlacement.allScreens()
        let connected = Set(placements.map { $0.displayID })

        for (id, controller) in screens where !connected.contains(id) {
            controller.close()
            screens[id] = nil
            levelWatchers[id] = nil
        }

        for placement in placements {
            let id = placement.displayID
            if let controller = screens[id] {
                controller.move(to: placement)
                continue
            }
            let model = makeModel(metrics: placement.metrics)
            let controller = NotchWindowController(model: model, placement: placement)
            controller.show()
            screens[id] = controller
            levelWatchers[id] = model.$level.sink { [weak self] level in
                self?.panelLevelChanged(level, on: id)
            }
        }
        if minimised {
            mailIcon.keepOnScreen()
        }
    }

    /// A new screen's notch starts with whatever the others already show.
    private func makeModel(metrics: NotchMetrics) -> NotchModel {
        let model = NotchModel(provider: SampleMailProvider(), metrics: metrics)
        // Gmail opens in Chrome, where the accounts are signed in; the notch gets out of its way.
        model.onOpenURL = { [weak model] url in
            BrowserOpener.open(url)
            model?.close()
        }
        model.onInstallUpdate = { [weak self] in
            self?.installUpdate()
        }
        model.onOpenMessage = { [weak self] id in
            self?.readInNotch(id)
        }
        model.onSetRead = { [weak self] id, read in
            self?.setRead(id, read: read)
        }
        model.onMarkAll = { [weak self] account, read in
            self?.markAll(account, read: read)
        }
        model.onUndoMarkAll = { [weak self] in
            self?.undoMarkAll()
        }
        model.tourPending = Tour.isPending()
        model.onTourFinished = { [weak self] in
            self?.tourFinished()
        }
        model.undoAccount = mailbox.undoAccount
        model.minimised = minimised
        model.phoneConnected = PhoneCableWatcher.shared.phone
        model.phoneBattery = PhoneCableWatcher.shared.details?.battery.map { "\($0.percent)%" }
        model.onMinimise = { [weak self] on in
            self?.setMinimised(on)
        }
        model.notesStore = notes
        model.timetableStore = timetable
        model.plannerStore = planner
        model.shelfStore = shelf
        model.bookmarksStore = bookmarks
        model.assignmentsStore = assignments
        model.onPlanAssignment = { [weak self] id in
            self?.planAssignment(id)
        }
        model.onReadAssignmentSheet = { [weak self, weak model] url in
            self?.readAssignmentSheet(url, for: model)
        }
        model.onPickAssignmentSheet = { [weak self, weak model] in
            self?.pickAssignmentSheet(for: model)
        }
        model.agentsStore = agents
        model.onStartAgent = { [weak self] name, task in
            self?.agentRunner.start(name: name, task: task, origin: .you)?.id
        }
        model.onStartChain = { [weak self] title, goal in
            self?.agentRunner.startChain(title: title, goal: goal, kind: .write, origin: .you)?.id
        }
        model.onCarryOnChain = { [weak self] id in
            self?.agentRunner.carryOn(id)?.id
        }
        model.onResearchAssignment = { [weak self] id in
            self?.researchAssignment(id)
        }
        model.onStopAgent = { [weak self] id in
            self?.agentRunner.stop(id)
        }
        model.onAgentAgain = { [weak self] id in
            self?.agentRunner.again(id)?.id
        }
        model.onRemoveAgent = { [weak self] id in
            self?.agentRunner.remove(id)
        }
        model.onClearAgents = { [weak self] in
            self?.agentRunner.clearFinished()
        }
        model.onShowAgentFolder = { [weak self] id in
            self?.showAgentFolder(id)
        }
        model.onOpenAgentFile = { [weak self] id, file in
            self?.openAgentFile(file, of: id)
        }
        model.recipesStore = recipes
        model.reportsStore = reports
        model.onShowReportFolder = { [weak self] folder in
            self?.showReportFolder(folder)
        }
        model.onOpenReportFile = { [weak self] folder, file in
            self?.openReportFile(file, in: folder)
        }
        model.teamStore = team
        model.onPostToTeam = { [weak self] text in
            self?.teamDesk.postFromYou(text)
        }
        model.onClearTeamChat = { [weak self] in
            self?.teamDesk.clear()
        }
        model.typingTarget = documentTyper.targetName
        if settings.showsLevels && settings.levelsAlways {
            model.steadyLevels = [LevelsWatcher.shared.volume, LevelsWatcher.shared.brightness].compactMap { $0?.rounded }
        }
        model.onTypeIntoDocument = { [weak self, weak model] text in
            self?.typeIntoDocument(text, from: model)
        }
        model.onUseSelection = { [weak self, weak model] in
            self?.useSelection(for: model)
        }
        model.onUseClipboard = { [weak model] in
            AppDelegate.useClipboard(for: model)
        }
        model.homeMenu = settings.homeMenu
        model.onArrangeHome = { [weak self] menu in
            self?.settings.homeMenu = menu
        }
        model.showsExtras = settings.showsExtras
        model.focusRunning = settings.showsFocus && FocusTimer.shared.session != nil
        model.customSizes = AppDelegate.loadPanelSizes()
        model.onResized = { [weak self] sizes in
            self?.panelResized(sizes)
        }
        model.wholeEmails = wholeEmails
        model.onShowInbox = { [weak self] account in
            self?.setHidden(false, for: account, atTheEnd: true)
        }
        model.onHideInbox = { [weak self] account in
            self?.setHidden(true, for: account)
        }
        model.onMoveInbox = { [weak self] account, offset in
            self?.moveInbox(account, by: offset, amongShown: true)
        }
        if lastFeedAt != nil {
            model.showLive(accounts: mailbox.accounts, messages: mailbox.messages, unread: mailbox.shownUnread, spare: spareInboxes)
        }
        model.pendingUpdate = updater.availableRelease?.build
        return model
    }

    /// Only one notch is open at a time: opening one closes any other.
    private func panelLevelChanged(_ level: NotchLevel, on id: CGDirectDisplayID) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshMailIcon()
        }
        guard level == .lanes || level == .detail else { return }
        for (other, controller) in screens where other != id && controller.model.level != .rest {
            controller.model.close()
        }
        // A good moment to notice that macOS's permission to press keys was given, or taken away.
        if DocumentTyper.isTrusted != settings.accessibilityAllowed {
            DispatchQueue.main.async { [weak self] in
                self?.checkAccessibility()
            }
        }
    }

    // MARK: Gmail via the browser add-on

    /// Each minute's feeds. The answer asks the add-on for the whole emails still missing.
    private func received(_ feeds: [AccountFeeds], upload: FeedUpload) -> LinkReply {
        // The version Chrome would load if the add-on reloaded; if the running add-on is
        // different, it reloads itself to catch up.
        let addOn = BrowserExtensionInstaller.installedVersion
        lastUpload = upload
        guard !feeds.isEmpty else {
            refreshSettings()
            return LinkReply(want: [], addon: addOn)
        }
        lastFeeds = feeds
        admitNewAccounts(feeds.map { $0.account })
        var showing: [GmailFeed] = []
        for account in feeds {
            let choice = inboxChoice(for: account.account)
            if appliedViews[account.account] != choice {
                switchView(of: account.account, from: appliedViews[account.account], to: choice)
            }
            showing.append(account.feed(showing: choice))
        }
        mailbox.apply(showing)
        UserDefaults.standard.set(mailbox.order, forKey: AppDelegate.accountOrderKey)
        if upload.version == nil {
            wholeEmails = .addOnNeedsReload
        } else {
            wholeEmails = upload.fullEmails == "on-open" ? .whenOpened : .coming
        }
        lastFeedAt = Date()
        showMailEverywhere()
        saveMailboxSoon()
        tidyEmailFiles()
        readMailForPlannerSoon()
        return LinkReply(want: mailbox.wanted(), addon: addOn, history: historyDays())
    }

    // MARK: Earlier mail, once

    /// Settings → Mail → "Fetch the Last 30 Days": the add-on is asked at its next visit.
    private func fetchHistory() {
        historyAskedAt = Date()
        historyAdded = 0
        historyHeardFrom = []
        settings.historyRunning = true
        settings.historyNote = "Asking your browser. A Gmail tab opens in the background for a moment for each inbox; this can take a couple of minutes."
        BrowserLink.wantsSync = true
    }

    /// How many days back to ask the add-on for, while a fetch is wanted. It's asked for
    /// up to ten minutes (an older add-on has to reload itself first), then given up on.
    private func historyDays() -> Int? {
        guard let asked = historyAskedAt else { return nil }
        if Date().timeIntervalSince(asked) > 600 {
            historyAskedAt = nil
            settings.historyRunning = false
            settings.historyNote = "Your browser didn't send anything back. Check Chrome is open and signed in to Gmail, then try again."
            return nil
        }
        return AssistantPrompt.mailDays
    }

    /// The add-on's list of earlier mail for one inbox.
    private func receivedHistory(_ upload: HistoryUpload) {
        guard settings.historyRunning else { return }
        let added = mailbox.addHistory(upload.items, account: upload.account, slot: upload.index ?? 0)
        historyAdded += added
        historyHeardFrom.insert(upload.account)
        if added > 0 {
            showMailEverywhere()
            saveMailboxSoon()
        }
        // Every inbox has answered: that's the one go done.
        if historyHeardFrom.isSuperset(of: mailbox.order) {
            historyAskedAt = nil
            settings.historyRunning = false
        }
        if let problem = upload.error, historyAdded == 0 {
            settings.historyNote = "Couldn't read Gmail's list: \(problem)"
        } else if historyAdded == 0 {
            settings.historyNote = "Nothing new: the notch already had the last \(AssistantPrompt.mailDays) days."
        } else {
            settings.historyNote = "Added \(historyAdded) earlier email\(historyAdded == 1 ? "" : "s") from the last \(AssistantPrompt.mailDays) days."
        }
    }

    /// An account is to show a different part of its inbox. Going from the Primary tab to the
    /// whole inbox keeps its mail (all of it is in the whole inbox too). Any other change
    /// starts the account afresh: mail kept from the other view isn't mail you read.
    private func switchView(of account: String, from before: InboxChoice?, to choice: InboxChoice) {
        if before == .primary && choice == .everything {
            mailbox.widen(account)
        } else {
            mailbox.forget(account)
        }
        appliedViews[account] = choice
    }

    /// You opened a real email in the notch: it's read here from now on (Gmail itself isn't
    /// changed), the unread count drops, and its whole text is shown: from disk if it was
    /// fetched before, otherwise it's fetched first.
    private func readInNotch(_ id: String) {
        mailbox.markOpened(id)
        let loaded = bringWholeIntoMemory(id)
        let wasUnread = mailbox.markReadHere(id)
        if loaded || wasUnread {
            showMailEverywhere()
        }
        if wasUnread {
            saveMailboxNow() // straight to disk, so it stays read even if the app quits next
        }
    }

    /// Reads an email's whole text back from disk, if it's there and not in memory already.
    /// Returns whether anything changed.
    @discardableResult
    private func bringWholeIntoMemory(_ id: String) -> Bool {
        guard mailbox.haveWhole.contains(id), mailbox.wholeInMemory(id) == nil else { return false }
        if let email = emailFiles.load(id) {
            mailbox.remember(email, for: id)
        } else {
            mailbox.lostWhole(id) // the file is gone: the add-on fetches it again
        }
        return true
    }

    /// Marks one real email read or unread in the notch's own tally.
    private func setRead(_ id: String, read: Bool) {
        let changed = read ? mailbox.markReadHere(id) : mailbox.markUnreadHere(id)
        if changed {
            showMailEverywhere()
            saveMailboxNow()
        }
    }

    /// Marks an inbox read or unread in the notch's own tally.
    private func markAll(_ account: String, read: Bool) {
        if read {
            mailbox.markAllRead(account)
        } else {
            mailbox.markAllUnread(account)
        }
        showMailEverywhere()
        saveMailboxNow()
    }

    private func undoMarkAll() {
        if mailbox.undoMarkAll() {
            showMailEverywhere()
            saveMailboxNow()
        }
    }

    /// A whole email (or news that it couldn't be fetched) from the add-on.
    private func received(_ email: EmailUpload) {
        if mailbox.storeWhole(email) {
            if email.html != nil || email.text != nil, let whole = mailbox.wholeInMemory(email.id) {
                emailFiles.save(whole, for: email.id)
            }
            showMailEverywhere()
            readMailForPlannerSoon()
        }
    }

    /// The linked inboxes that aren't in the notch, for "Add an inbox".
    private var spareInboxes: [NotchModel.SpareInbox] {
        mailbox.spareAccounts.map { NotchModel.SpareInbox(id: $0, name: LiveMailbox.label(for: $0)) }
    }

    private func showMailEverywhere() {
        // Whatever each screen has open keeps its whole text in memory.
        for model in models {
            if let id = model.openMessageID {
                bringWholeIntoMemory(id)
            }
        }
        let accounts = mailbox.accounts
        let messages = mailbox.messages
        let unread = mailbox.shownUnread
        let undo = mailbox.undoAccount
        let spare = spareInboxes
        for model in models {
            model.showLive(accounts: accounts, messages: messages, unread: unread, spare: spare)
            if model.undoAccount != undo {
                model.undoAccount = undo
            }
            if model.wholeEmails != wholeEmails {
                model.wholeEmails = wholeEmails
            }
        }
        refreshMailIcon()
        refreshSettings()
    }

    // MARK: Mail kept on this Mac

    /// Keeps the newest whole emails on disk, up to the limit in Settings, and clears away
    /// any whose email the notch no longer has. Waits for the add-on's first sync, so a
    /// mailbox that failed to load can't be mistaken for an empty one.
    private func tidyEmailFiles(force: Bool = false) {
        guard lastUpload != nil else { return }
        let limit = settings.wholeEmailLimit
        let onDisk = emailFiles.ids.count
        guard force || !tidiedEmailFiles || (limit > 0 && onDisk > limit + 25) else { return }
        tidiedEmailFiles = true
        emailFiles.keep(mailbox.idsNewestFirst, limit: limit)
        mailbox.setSavedWhole(emailFiles.ids)
        measureStorage()
    }

    /// Works out how much mail is kept, for Settings.
    private func measureStorage() {
        let history = mailbox.history
        emailFiles.measure { [weak self] count, bytes in
            guard let self = self else { return }
            let storage = AppSettings.Storage(emails: history.emails, oldest: history.oldest, whole: count, bytes: bytes)
            if self.settings.storage != storage {
                self.settings.storage = storage
            }
        }
    }

    // MARK: Extras

    /// Starts or stops each extra as Settings says, and tells every notch whether the row shows.
    private func applyExtras() {
        if settings.showsNowPlaying {
            NowPlayingWatcher.shared.start()
        } else {
            NowPlayingWatcher.shared.stop()
        }
        if settings.keepsClipboard {
            ClipboardWatcher.shared.start()
        } else {
            ClipboardWatcher.shared.stop() // forgets what it held
        }
        if !settings.showsFocus {
            FocusTimer.shared.stop()
        }
        for model in models {
            if model.showsExtras != settings.showsExtras {
                model.showsExtras = settings.showsExtras
            }
            if model.tool == .extras && !settings.showsExtras {
                model.goHome()
            }
        }
        focusChanged(FocusTimer.shared.session)
    }

    private func focusChanged(_ session: FocusSession?) {
        let running = settings.showsFocus && session != nil
        for model in models where model.focusRunning != running {
            model.focusRunning = running
        }
    }

    /// A round of focus or a break ran out: a chime, and the notch opens to say so.
    private func focusFinished(_ session: FocusSession) {
        NSSound(named: NSSound.Name("Glass"))?.play()
        guard let model = notchNearPointer(), model.level == .rest || model.level == .peek else { return }
        model.goHome()
    }

    // MARK: Agents and the chief of staff

    /// What the assistant can see and change besides the timetable and planner: its team
    /// of agents, your assignments and marks, your bookmarks. Each can be switched off in
    /// Settings → Assistant.
    private func connectAgents() {
        let assistant = Assistant.shared
        let staff = Assistant.Ability(
            tag: StaffAgent.tag,
            title: "Hand jobs to agents",
            detail: "It can start agents on bigger jobs, stop them, read their reports, and see your recipes.",
            instructions: { [weak self] in
                let tools = Assistant.shared.engine == .claudeCode
                return StaffAgent.instructions(tools: tools, web: tools && (self?.settings.agentsUseWeb ?? false))
            },
            describe: { [weak self] in
                guard let self = self else { return "" }
                return StaffAgent.describe(self.agents.team, recipes: self.recipes.book, kept: self.reports.library.reports.count, now: Date())
            },
            apply: { [weak self] json in
                // Handed out from the chat that's open: that's where the reports come back to.
                self?.applyStaff(json, chat: Assistant.shared.chats.book.currentID)
            },
            heading: "In the Agents room",
            nothing: "(No agents needed starting.)")
        let work = Assistant.Ability(
            tag: AssignmentAgent.tag,
            title: "Assignments and marks",
            detail: "It can see your assignments and marks, add to them and record marks.",
            instructions: { AssignmentAgent.instructions },
            describe: { [weak self] in
                guard let self = self else { return "" }
                return AssignmentAgent.describe(self.assignments.assignments, now: Date())
            },
            apply: { [weak self] json in
                guard let self = self, let plan = AssignmentAgent.plan(from: json) else { return nil }
                var changes: [String] = []
                self.assignments.change { changes = AssignmentAgent.apply(plan, to: &$0, now: Date()) }
                return changes
            },
            heading: "Assignments updated",
            nothing: "(Your assignments already had that.)")
        let links = Assistant.Ability(
            tag: BookmarkAgent.tag,
            title: "Bookmarks",
            detail: "It can see your bookmarks, add links and remove them.",
            instructions: { BookmarkAgent.instructions },
            describe: { [weak self] in
                guard let self = self else { return "" }
                return BookmarkAgent.describe(self.bookmarks.bookmarks)
            },
            apply: { [weak self] json in
                guard let self = self, let plan = BookmarkAgent.plan(from: json) else { return nil }
                return BookmarkAgent.apply(plan, to: self.bookmarks, now: Date())
            },
            heading: "Bookmarks updated",
            nothing: "(Your bookmarks already had that.)")
        assistant.abilities = [staff, work, links]

        // The team chat: the chief answers there with the jobs and your assignments to hand
        // (not your mail or notes), and may start agents only when it's you who asked.
        teamDesk.extra = { [weak self] in
            guard let self = self, Assistant.shared.allows(AssignmentAgent.tag) else { return "" }
            return AssignmentAgent.describe(self.assignments.assignments, now: Date())
        }
        // (Agents started from the team chat report there, not to one of your chats.)
        teamDesk.applyStaff = { [weak self] json in
            self?.applyStaff(json, chat: nil)
        }
        agentRunner.desk = teamDesk

        agentRunner.onFinished = { [weak self] job in
            self?.agentFinished(job)
        }
        // The library starts with the reports of the agents still in the room.
        if reports.isNew {
            let known = assignments.assignments
            reports.change { library in
                library.fill(from: agents.team, subject: { assignment in known.item(assignment)?.subject ?? "" })
            }
        }
        // More agents may work at once now: start the ones that were waiting.
        settings.onAgentsChanged = { [weak self] in
            self?.agentRunner.pump()
        }
        settings.onChooseAgentFolder = { [weak self] in
            self?.chooseAgentFolder()
        }
        settings.onShowAgentsFolder = {
            let home = AgentBrief.home
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            NSWorkspace.shared.open(home)
        }
    }

    /// What the assistant asked of its agents: stop these, start those. `chat` is the chat
    /// it asked from, where the new agents' reports go when they finish.
    private func applyStaff(_ json: String, chat: UUID?) -> [String]? {
        guard let plan = StaffAgent.plan(from: json) else { return nil }
        let reportsTo = settings.agentsReportBack ? chat : nil
        var changes: [String] = []
        for job in StaffAgent.stops(in: plan, team: agents.team) {
            agentRunner.stop(job.id)
            changes.append("\(job.name) stopped")
        }
        for job in StaffAgent.jobs(in: plan) {
            if let kind = job.chain {
                // A researcher now; the others follow by themselves. A plan for an
                // assignment in your list gets its task sheet too (if the assistant
                // may see your assignments), and shows on that assignment.
                var goal = job.task
                var source: UUID?
                if Assistant.shared.allows(AssignmentAgent.tag),
                   let item = StaffAgent.assignment(for: job, in: assignments.assignments) {
                    goal = StaffAgent.planGoal(for: job, item: item, now: Date())
                    source = item.id
                }
                if let started = agentRunner.startChain(title: job.name, goal: goal, kind: kind, origin: .chief, source: source, chat: reportsTo) {
                    changes.append("\(started.name) started (a chain: \(AgentChain.line(for: kind)))")
                }
            } else if let started = agentRunner.start(name: job.name, task: job.task, origin: .chief, chat: reportsTo) {
                changes.append("\(started.name) started")
            }
        }
        return changes
    }

    /// An agent finished or couldn't. If the assistant handed its job out from a chat, its
    /// report goes back to that chat. And a chime, if that's on. (Neither for one you
    /// stopped, nor for a stage of a chain that the next agent is carrying on from.)
    private func agentFinished(_ job: AgentJob) {
        // Its report is kept in the library (each stage of a chain, under the chain's name).
        if job.status == .done {
            let subject = assignments.assignments.item(job.chain?.source)?.subject ?? ""
            reports.change { $0.file(job, subject: subject) }
        }
        if settings.agentsReportBack, AgentDelivery.reports(job) {
            let watched = models.contains { $0.tool == .assistant && ($0.level == .lanes || $0.level == .detail) }
            Assistant.shared.deliver(AgentDelivery.message(for: job, team: agents.team), from: job.id, to: job.chat, watched: watched)
        }
        guard settings.agentsChime, job.status == .done || job.status == .failed, !job.isHandingOn else { return }
        NSSound(named: NSSound.Name(job.status == .done ? "Glass" : "Basso"))?.play()
    }

    /// "Research This" on an assignment: a researcher, a planner and a checker take it on
    /// in turn, from its name, due date and task sheet. They plan it; the writing stays yours.
    private func researchAssignment(_ id: UUID) -> UUID? {
        guard let item = assignments.assignments.item(id), AgentChain.canResearch(item) else { return nil }
        let goal = AgentChain.goal(for: item, now: Date())
        return agentRunner.startChain(title: item.title, goal: goal, kind: .assignment, origin: .you, source: id)?.id
    }

    /// Shows an agent's own folder in Finder.
    private func showAgentFolder(_ id: UUID) {
        guard let job = agents.team.job(id), !job.folder.isEmpty else { return }
        let folder = URL(fileURLWithPath: job.folder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(folder)
    }

    /// Opens a file an agent saved. Only plain documents open straight away; anything that
    /// could run (a web page, a script) is shown in Finder instead.
    private func openAgentFile(_ file: String, of id: UUID) {
        guard let job = agents.team.job(id), let path = AgentFiles.path(of: file, in: job.folder),
              FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        let url = URL(fileURLWithPath: path)
        if AgentFiles.opensDirectly(file) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Shows the folder kept with a report in the library. (Only an agent's own folder:
    /// the library's file is the app's, but nothing outside the agents' folders opens from it.)
    private func showReportFolder(_ folder: String) {
        guard ReportLibrary.isAgentsFolder(folder), FileManager.default.fileExists(atPath: folder) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true))
    }

    /// Opens a file kept with a report, by the same rule as an agent's files: plain
    /// documents open, and anything that could run is shown in Finder instead.
    private func openReportFile(_ file: String, in folder: String) {
        guard ReportLibrary.isAgentsFolder(folder), let path = AgentFiles.path(of: file, in: folder),
              FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        let url = URL(fileURLWithPath: path)
        if AgentFiles.opensDirectly(file) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Settings → Assistant → "Add a folder": a folder of yours agents may read.
    private func chooseAgentFolder() {
        // The notch sits above other windows: close it so the folder chooser isn't under it.
        let asking = models.first { $0.level != .rest }
        for model in models where model.level != .rest {
            model.close()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.prompt = "Let Agents Read"
            panel.message = "Choose a folder your agents may read. They can't change anything in it."
            if panel.runModal() == .OK, let url = panel.url {
                self.settings.addAgentFolder(url.path)
            }
            // Back to Settings, to see it in the list (or why it wasn't taken).
            (asking ?? self.notchNearPointer())?.openSettings(.assistant)
        }
    }

    // MARK: Volume and brightness

    private func connectLevels() {
        LevelsWatcher.shared.onShow = { [weak self] reading in
            self?.showLevel(reading)
        }
        mediaKeys.handle = { [weak self] press, fine in
            self?.mediaKey(press, fine: fine) ?? false
        }
        settings.onLevelsChanged = { [weak self] in
            self?.applyLevels()
        }
        settings.onAskForAccessibility = { [weak self] in
            self?.askForAccessibility()
        }
        settings.onCheckAccessibility = { [weak self] in
            self?.checkAccessibility()
        }
        // The gauges that stay beside the closed notch follow the volume and brightness.
        LevelsWatcher.shared.$volume
            .combineLatest(LevelsWatcher.shared.$brightness)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume, brightness in
                self?.showSteadyLevels(volume: volume, brightness: brightness)
            }
            .store(in: &subscriptions)
        applyLevels()
    }

    /// Keeps the always-on gauges up to date, or takes them away if they're switched off.
    private func showSteadyLevels(volume: LevelReading?, brightness: LevelReading?) {
        var levels: [LevelReading] = []
        if settings.showsLevels && settings.levelsAlways {
            levels = [volume, brightness].compactMap { $0?.rounded }
        }
        for model in models where model.steadyLevels != levels {
            model.steadyLevels = levels
        }
    }

    /// Starts or stops watching the volume and brightness, as Settings → Extras says.
    private func applyLevels() {
        if settings.showsLevels {
            LevelsWatcher.shared.start()
        } else {
            LevelsWatcher.shared.stop()
            hideLevel()
        }
        showSteadyLevels(volume: LevelsWatcher.shared.volume, brightness: LevelsWatcher.shared.brightness)
        checkAccessibility()
    }

    /// Shows a level beside the closed notch for a moment.
    private func showLevel(_ reading: LevelReading) {
        guard settings.showsLevels else { return }
        LevelsWatcher.shared.showing = reading.kind
        for model in models where model.levelHUD != reading {
            model.levelHUD = reading
        }
        levelHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideLevel()
        }
        levelHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func hideLevel() {
        levelHide?.cancel()
        levelHide = nil
        LevelsWatcher.shared.showing = nil
        for model in models where model.levelHUD != nil {
            model.levelHUD = nil
        }
    }

    /// A volume or brightness key, with the keys taken over. True if the notch dealt with
    /// it; false sends it on to macOS as usual.
    private func mediaKey(_ press: MediaKey.Press, fine: Bool) -> Bool {
        let watcher = LevelsWatcher.shared
        guard settings.showsLevels, settings.replacesSystemLevels, watcher.isRunning, watcher.canChange(press.key.kind) else { return false }
        // Letting go, or the mute key held down: nothing more to do, and macOS needn't see it.
        if !press.down || (press.key == .mute && press.repeated) {
            return true
        }
        return watcher.press(press.key, fine: fine)
    }

    // MARK: Accessibility permission

    /// Looks at whether macOS lets the app press keys in other apps, and starts or stops
    /// the taking-over of the volume keys to match. While the permission is being waited
    /// for, it looks again every couple of seconds.
    private func checkAccessibility() {
        let allowed = DocumentTyper.isTrusted
        if settings.accessibilityAllowed != allowed {
            settings.accessibilityAllowed = allowed
        }
        let wanted = settings.showsLevels && settings.replacesSystemLevels
        if wanted && allowed {
            if !mediaKeys.isRunning {
                mediaKeys.start()
            }
        } else if mediaKeys.isRunning {
            mediaKeys.stop()
        }
        accessibilityCheck?.cancel()
        accessibilityCheck = nil
        guard !allowed, accessibilityChecksLeft > 0 else {
            accessibilityChecksLeft = 0
            return
        }
        accessibilityChecksLeft -= 1
        let work = DispatchWorkItem { [weak self] in
            self?.checkAccessibility()
        }
        accessibilityCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Asks macOS for the permission. An entry left by an earlier build no longer matches
    /// this one (each update is a new build to macOS), so it's cleared first; then macOS
    /// shows its own prompt, with a button that opens the right page of System Settings.
    private func askForAccessibility() {
        if !DocumentTyper.isTrusted, let id = Bundle.main.bundleIdentifier {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", id]
            reset.standardOutput = FileHandle.nullDevice
            reset.standardError = FileHandle.nullDevice
            if (try? reset.run()) != nil {
                reset.waitUntilExit()
            }
        }
        // The notch sits above other windows: close it so macOS's prompt isn't under it.
        for model in models where model.level != .rest {
            model.close()
        }
        DocumentTyper.askForAccess()
        // Look for the answer for the next five minutes.
        accessibilityChecksLeft = 150
        checkAccessibility()
    }

    // MARK: Typing into your documents

    private func connectTyping() {
        documentTyper.onTargetChanged = { [weak self] name in
            for model in self?.models ?? [] where model.typingTarget != name {
                model.typingTarget = name
            }
        }
        documentTyper.start()
        for model in models {
            model.typingTarget = documentTyper.targetName
        }
    }

    /// Types an answer where your cursor is. If macOS doesn't let the app press keys, the
    /// answer is left on the clipboard and the chat says to paste it.
    private func typeIntoDocument(_ text: String, from model: NotchModel?) {
        documentTyper.typeText(text, closeNotch: { model?.close() }) { [weak self] outcome in
            self?.checkAccessibility()
            if case .typed = outcome { return }
            model?.typingNote = outcome.note
        }
    }

    /// Attaches what's selected in the app you were in to your next question.
    private func useSelection(for model: NotchModel?) {
        checkAccessibility()
        guard DocumentTyper.isTrusted else {
            model?.typingNote = DocumentText.needsAccess
            return
        }
        let app = documentTyper.targetName ?? ""
        documentTyper.selection { text in
            if let found = DocumentText.selection(text, app: app, source: .selection) {
                Assistant.shared.attachment = found
            } else {
                model?.typingNote = DocumentText.nothingSelected(in: app)
            }
        }
    }

    /// Attaches what you've copied to your next question. The clipboard is only read when
    /// you click the button, and a copy marked private (a password) is left alone.
    private static func useClipboard(for model: NotchModel?) {
        let pasteboard = NSPasteboard.general
        if ClipList.isPrivate(types: (pasteboard.types ?? []).map { $0.rawValue }) {
            model?.typingNote = DocumentText.privateCopy
        } else if let found = DocumentText.selection(pasteboard.string(forType: .string), app: "", source: .clipboard) {
            Assistant.shared.attachment = found
        } else {
            model?.typingNote = DocumentText.nothingCopied
        }
    }

    // MARK: Planner

    /// Looks through the mail for homework and exams, a few seconds after the last change
    /// (whole emails arrive in bursts).
    private func readMailForPlannerSoon() {
        plannerMailWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.readMailForPlanner()
        }
        plannerMailWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func readMailForPlanner() {
        plannerMailWork = nil
        // Only real mail: nothing is read until the browser link has delivered some.
        guard lastFeedAt != nil else { return }
        let messages = mailbox.messages
        let held = mailbox
        let files = emailFiles
        plannerMail.read(messages, haveWhole: held.haveWhole, whole: { id in
            held.wholeInMemory(id) ?? files.load(id)
        })
    }

    /// Homework and revision fitted into free time, if that's switched on.
    private func studyPlan() -> [StudySession] {
        guard settings.plansStudy else { return [] }
        return StudyPlanner.plan(tasks: planner.planner.tasks + assignments.assignments.planTasks(), exams: planner.planner.exams,
                                 timetable: timetable.timetable, now: Date(), daily: settings.studyMinutesADay)
    }

    // MARK: Assistant

    /// What the assistant may know about your day: your newest real emails and latest notes.
    private func assistantContext() -> String {
        var emails: [(account: String, sender: String, subject: String, date: Date, unread: Bool)] = []
        var previews: [String] = []
        if let model = models.first, !model.isSample {
            // Everything the notch holds from the last month, for the inboxes that are showing.
            let shown = Set(model.accounts.map { $0.id })
            let since = Date().addingTimeInterval(-Double(AssistantPrompt.mailDays) * 86_400)
            let month = mailbox.messages
                .filter { shown.contains($0.accountID) && $0.date >= since }
                .sorted { $0.date > $1.date }
                .prefix(AssistantPrompt.mostMail)
            emails = month.map { (account: model.account($0.accountID)?.name ?? $0.accountID,
                                  sender: $0.sender, subject: $0.subject, date: $0.date, unread: $0.isUnread) }
            previews = month.prefix(AssistantPrompt.mostPreviews).map { $0.snippet }
        }
        let recentNotes = notes.notes
            .filter { !$0.isEmpty }
            .prefix(10)
            .map { (title: $0.title, preview: $0.preview) }
        // The timetable goes in separately, with its own setting (and so the assistant can change it).
        return AssistantPrompt.context(emails: emails, notes: Array(recentNotes), previews: previews, limit: AssistantPrompt.mostMail, now: Date())
    }

    // MARK: Phone by cable

    private func phoneChanged(_ phone: String?) {
        for model in models where model.phoneConnected != phone {
            model.phoneConnected = phone
        }
    }

    private func phoneDetailsChanged(_ details: PhoneDetails?) {
        let battery = details?.battery.map { "\($0.percent)%" }
        for model in models where model.phoneBattery != battery {
            model.phoneBattery = battery
        }
    }

    // MARK: Minimised to a mail icon

    private func setMinimised(_ on: Bool) {
        minimised = on
        UserDefaults.standard.set(on, forKey: AppDelegate.minimisedKey)
        for model in models {
            if on {
                model.close()
            }
            model.minimised = on
        }
        if on {
            mailIcon.show()
        } else {
            mailIcon.hide()
        }
        refreshMailIcon()
    }

    /// The minimised tab hides while the panel is open, and comes back when it closes.
    private func refreshMailIcon() {
        guard minimised else { return }
        let somethingOpen = models.contains { $0.level != .rest }
        if somethingOpen {
            mailIcon.conceal()
        } else {
            mailIcon.reveal()
        }
    }

    // MARK: Assignments

    /// Has the assistant break an assignment into steps. Its name, subject, due date, task
    /// sheet and notes go to the assistant (to Anthropic, with Claude); nothing else does.
    /// If the assistant isn't set up or can't, the usual steps for that kind of work go in.
    private func planAssignment(_ id: UUID) {
        guard let item = assignments.assignments.item(id) else { return }
        let assistant = Assistant.shared
        guard assistant.status.isReady else {
            finishPlanning(id, steps: nil, problem: "\(assistant.engine.name) isn't set up yet (Settings → Assistant).")
            return
        }
        let prompt = AssignmentBreakdown.prompt(for: item, now: Date())
        let model = assistant.claudeModel
        Task { [weak self] in
            let result = await assistant.complete(system: AssignmentBreakdown.system, prompt: prompt, model: model)
            guard let self = self else { return }
            await MainActor.run {
                switch result {
                case .success(let answer):
                    self.finishPlanning(id, steps: AssignmentBreakdown.parse(answer), problem: "The assistant's plan couldn't be read.")
                case .failure(let problem):
                    self.finishPlanning(id, steps: nil, problem: problem.message)
                }
            }
        }
    }

    // MARK: A task sheet

    /// Reads a file as a task sheet: its words are got out here on the Mac, the assistant
    /// picks out the title, due date, weighting and steps, and a new assignment opens to
    /// be checked. If the assistant can't be asked, the assignment is still made, named
    /// after the file with the sheet's words as its brief.
    private func readAssignmentSheet(_ url: URL, for model: NotchModel?) {
        let name = url.lastPathComponent
        let assistant = Assistant.shared
        let ready = assistant.status.isReady
        Task.detached { [weak self] in
            let text = SheetReader.text(of: url)
            guard let self = self else { return }
            guard !text.isEmpty else {
                await MainActor.run {
                    if let model = model {
                        model.finishSheet(nil, note: AssignmentSheet.noWords)
                    }
                }
                return
            }
            var found: AssignmentSheet.Found?
            var note: String?
            if ready {
                let result = await assistant.complete(system: AssignmentSheet.system,
                                                      prompt: AssignmentSheet.prompt(text: text, fileName: name, now: Date()),
                                                      maxTokens: 1800)
                switch result {
                case .success(let answer):
                    found = AssignmentSheet.parse(answer, now: Date())
                    if found == nil {
                        note = "The assistant's reading of the sheet couldn't be understood, so its words are in the brief for you to fill in the rest."
                    }
                case .failure(let problem):
                    note = "The sheet's words are in the brief, but the rest is for you to fill in: \(problem.message)"
                }
            } else {
                note = "\(assistant.engine.name) isn't set up yet, so the sheet's words are in the brief and the rest is for you to fill in."
            }
            let item = AssignmentSheet.assignment(found, text: text, fileName: name)
            let why = note
            await MainActor.run {
                self.assignments.change { $0.add(item) }
                if let model = model {
                    model.finishSheet(item.id, note: why)
                }
            }
        }
    }

    /// The button in Assignments: choose the sheet's file, then read it.
    private func pickAssignmentSheet(for model: NotchModel?) {
        // The notch sits above other windows: close it so the file chooser isn't under it.
        for open in models where open.level != .rest {
            open.close()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Read Sheet"
            panel.message = "Choose the task sheet: a PDF, a Word or text file, or a photo or screenshot of it."
            let picked = panel.runModal() == .OK ? panel.url : nil
            let target = model ?? self.notchNearPointer()
            target?.openAssignments()
            if let url = picked {
                target?.readAssignmentSheet(url)
            }
        }
    }

    private func finishPlanning(_ id: UUID, steps: [AssignmentStep]?, problem: String) {
        for model in models {
            model.finishPlanning(id, steps: steps, problem: problem)
        }
    }

    // MARK: The primary menu

    /// Gives every screen's notch the arrangement chosen in Settings (or by right-clicking
    /// a tile). A size the menu was dragged to for a different number of tiles would squash
    /// them or leave a gap, so that goes back to standard.
    private func applyHomeMenu() {
        let menu = settings.homeMenu
        for model in models where model.homeMenu != menu {
            model.homeMenu = menu
        }
        var sizes = models.first?.customSizes ?? [:]
        if sizes[.peek] != nil && UserDefaults.standard.integer(forKey: AppDelegate.peekClassKey) != menu.sizeClass {
            sizes[.peek] = nil
            panelResized(sizes)
        }
    }

    // MARK: Panel sizes

    /// How many tiles the primary menu had (as a size class) when you dragged it to a size.
    private static let peekClassKey = "panelSizes.peekTiles"

    private static func loadPanelSizes() -> [NotchLevel: CGSize] {
        var saved = UserDefaults.standard.dictionary(forKey: panelSizesKey) as? [String: [Double]] ?? [:]
        // The primary menu gained a row (build 30): a size dragged before then would squash
        // it, so that one size goes back to standard, once.
        if !UserDefaults.standard.bool(forKey: "panelSizes.madeRoomForExtras") {
            UserDefaults.standard.set(true, forKey: "panelSizes.madeRoomForExtras")
            if saved[NotchLevel.peek.rawValue] != nil {
                saved[NotchLevel.peek.rawValue] = nil
                UserDefaults.standard.set(saved, forKey: panelSizesKey)
            }
        }
        // The same when the menu has a different number of tiles than it was dragged for
        // (a new tool arrived with an update, say).
        if saved[NotchLevel.peek.rawValue] != nil
            && UserDefaults.standard.integer(forKey: peekClassKey) != HomeMenu(defaults: .standard).sizeClass {
            saved[NotchLevel.peek.rawValue] = nil
            UserDefaults.standard.set(saved, forKey: panelSizesKey)
        }
        var sizes: [NotchLevel: CGSize] = [:]
        for (key, value) in saved {
            if let level = NotchLevel(rawValue: key), value.count == 2 {
                sizes[level] = CGSize(width: value[0], height: value[1])
            }
        }
        return sizes
    }

    /// Remembers a dragged size and gives every screen's notch the same one.
    private func panelResized(_ sizes: [NotchLevel: CGSize]) {
        var saved: [String: [Double]] = [:]
        for (level, size) in sizes {
            saved[level.rawValue] = [Double(size.width), Double(size.height)]
        }
        UserDefaults.standard.set(saved, forKey: AppDelegate.panelSizesKey)
        if sizes[.peek] != nil {
            UserDefaults.standard.set(settings.homeMenu.sizeClass, forKey: AppDelegate.peekClassKey)
        }
        for model in models where model.customSizes != sizes {
            model.customSizes = sizes
        }
    }

    /// Clicking the minimised tab opens the primary menu at the notch of the screen it's
    /// on, or closes whatever is open there.
    private func openFromMailIcon() {
        let screen = mailIcon.screen
        let target = screens.values.first(where: { $0.screen == screen }) ?? screens.values.first
        guard let model = target?.model else { return }
        if model.level == .rest {
            model.goHome()
        } else {
            model.close()
        }
    }

    // MARK: Settings

    /// What Settings' buttons do.
    private func connectSettings() {
        settings.build = updater.currentBuild
        settings.onChooseInbox = { [weak self] account, choice in
            self?.chooseInbox(choice, for: account)
        }
        settings.onSetHidden = { [weak self] account, hidden in
            self?.setHidden(hidden, for: account)
        }
        settings.onMoveAccount = { [weak self] account, offset in
            self?.moveInbox(account, by: offset, amongShown: false)
        }
        settings.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        settings.onInstallUpdate = { [weak self] in
            self?.installUpdate()
        }
        // "Get test builds" was switched: look again straight away, the new way.
        settings.onTestBuildsChanged = { [weak self] in
            guard let self = self else { return }
            self.updater.testBuilds = self.settings.testBuilds
            self.updater.check()
        }
        settings.onOpenReleasePage = { [weak self] in
            guard let self = self else { return }
            NSWorkspace.shared.open(self.updater.releasePage)
        }
        settings.onSetUpBrowserLink = { [weak self] in
            self?.setUpBrowserLink()
        }
        settings.onCopyDebugInfo = { [weak self] in
            self?.copyDebugInfo()
        }
        settings.onShowAddOnFolder = { [weak self] in
            self?.showAddOnFolder()
        }
        settings.onQuit = { [weak self] in
            self?.quit()
        }
        settings.onStorageLimitChanged = { [weak self] in
            self?.tidyEmailFiles(force: true)
        }
        settings.onMeasureStorage = { [weak self] in
            self?.measureStorage()
        }
        refreshSettings()
    }

    /// Keeps Settings' accounts and Gmail link status in step with the mailbox.
    private func refreshSettings() {
        let shown = mailbox.accounts
        var colors: [String: UInt32] = [:]
        for account in shown {
            colors[account.id] = account.colorHex
        }
        let accounts = AppSettings.accounts(linked: mailbox.linkedAccounts, shown: shown.map { $0.id },
                                            hidden: mailbox.hidden, choices: { self.inboxChoice(for: $0) },
                                            unread: mailbox.shownUnread, colors: colors)
        if settings.accounts != accounts {
            settings.accounts = accounts
        }
        var link = AppSettings.LinkStatus()
        link.lastSync = lastFeedAt
        link.accounts = mailbox.linkedAccounts.count
        link.addOnRunning = lastUpload.map { $0.version ?? "1.0" }
        link.addOnInstalled = BrowserExtensionInstaller.installedVersion
        link.needsReload = wholeEmails == .addOnNeedsReload
        if settings.link != link {
            settings.link = link
        }
        let checked = updater.lastCheck?.at
        if settings.lastUpdateCheck != checked {
            settings.lastUpdateCheck = checked
        }
    }

    // MARK: Accounts

    private static func loadInboxChoices() -> [String: InboxChoice] {
        let saved = UserDefaults.standard.dictionary(forKey: AppDelegate.inboxChoicesKey) as? [String: String] ?? [:]
        return saved.compactMapValues { InboxChoice(rawValue: $0) }
    }

    private func saveInboxChoices() {
        UserDefaults.standard.set(inboxChoices.mapValues { $0.rawValue }, forKey: AppDelegate.inboxChoicesKey)
    }

    private func inboxChoice(for account: String) -> InboxChoice {
        inboxChoices[account] ?? InboxChoice.starting(for: account)
    }

    /// Primary (plus Google mail) or the whole inbox, for one account.
    private func chooseInbox(_ choice: InboxChoice, for account: String) {
        let before = inboxChoice(for: account)
        inboxChoices[account] = choice
        saveInboxChoices()
        guard choice != before else {
            refreshSettings()
            return
        }
        // Swap the account's mail straight away from the latest feeds.
        switchView(of: account, from: before, to: choice)
        mailbox.apply(lastFeeds.filter { $0.account == account }.map { $0.feed(showing: choice) })
        showMailEverywhere()
        saveMailboxSoon()
    }

    /// Takes an inbox out of the notch, or puts it back. Added from Mail ("Add an inbox"),
    /// it goes after the inboxes already there; switched on in Settings, it keeps its place
    /// in the list.
    private func setHidden(_ hidden: Bool, for account: String, atTheEnd: Bool = false) {
        if hidden {
            // The notch always keeps one inbox.
            guard mailbox.accounts.count > 1 || !mailbox.accounts.contains(where: { $0.id == account }) else {
                // Settings' switch flipped by itself when clicked: put it back.
                settings.objectWillChange.send()
                return
            }
            mailbox.hidden.insert(account)
        } else {
            if atTheEnd, mailbox.moveAfterShown(account) {
                UserDefaults.standard.set(mailbox.order, forKey: AppDelegate.accountOrderKey)
                saveMailboxSoon()
            }
            mailbox.hidden.remove(account)
        }
        UserDefaults.standard.set(Array(mailbox.hidden).sorted(), forKey: AppDelegate.hiddenAccountsKey)
        showMailEverywhere()
        if !hidden {
            // An inbox that's just been added may hold homework for the planner.
            readMailForPlannerSoon()
        }
    }

    /// Accounts seen for the first time. The notch starts with one inbox: the first account
    /// ever linked shows by itself, and any other waits until you add it ("Add an inbox" in
    /// Mail, or Settings → Mail accounts).
    private func admitNewAccounts(_ accounts: [String]) {
        guard !mailbox.admit(accounts, met: &metAccounts).isEmpty else { return }
        UserDefaults.standard.set(Array(mailbox.hidden).sorted(), forKey: AppDelegate.hiddenAccountsKey)
        UserDefaults.standard.set(Array(metAccounts).sorted(), forKey: AppDelegate.metAccountsKey)
    }

    /// Moves an account one place earlier or later: among the inboxes in the notch (from
    /// Mail), or among every linked account (from Settings).
    private func moveInbox(_ account: String, by offset: Int, amongShown: Bool) {
        let accounts = amongShown ? mailbox.accounts.map { $0.id } : mailbox.linkedAccounts
        guard let other = LiveMailbox.neighbour(of: account, by: offset, among: accounts),
              mailbox.swapPlaces(account, other) else { return }
        UserDefaults.standard.set(mailbox.order, forKey: AppDelegate.accountOrderKey)
        showMailEverywhere()
        saveMailboxSoon()
    }

    /// Only one copy runs at a time: the one just opened (after an update, say) takes over
    /// from any other copy still running, which would otherwise keep the browser link.
    private func endOtherCopies() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
    }

    // MARK: Debugging

    /// Copies a plain report of what the app and the browser add-on are doing: builds,
    /// update checks, and per account what Gmail's feeds say and what the notch holds.
    /// Counts and addresses only, no email contents.
    private func copyDebugInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugReport(), forType: .string)
        showUpdateNote("Debug info copied", clearAfter: 3)
    }

    private func debugReport() -> String {
        var lines: [String] = []
        lines.append("Notch Inbox build \(updater.currentBuild) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        var update = "Updates: \(AppDelegate.describe(updater.state)) · test builds \(settings.testBuilds ? "on" : "off")"
        update += " · released to everyone: \(updater.releasedBuild.map { "build \($0)" } ?? "not known")"
        if let check = updater.lastCheck {
            update += " · last check \(MailTime.label(for: check.at)) (\(check.result))"
        }
        lines.append(update)
        lines.append("Browser link: \(browserLink.status)")
        let assistant = Assistant.shared
        lines.append("Assistant: \(assistant.engine.title) · \(assistant.modelName) · \(assistant.status)"
                     + (assistant.engine == .claudeCode ? " · Claude Code at \(assistant.claudePath ?? "not found")" : ""))
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").count
        lines.append("Copies of the app running: \(copies) · app at \(Bundle.main.bundlePath)")
        lines.append("Tour: \(Tour.isPending() ? "not finished yet" : "finished or skipped") · \(Tour.opensAtLaunch() ? "will open at the next launch" : "has opened by itself already")")
        let menu = settings.homeMenu
        let offMenu = menu.order.filter { !menu.isShown($0) }.map { $0.title }
        lines.append("Primary menu: \(menu.shown.map { $0.title }.joined(separator: ", "))\(offMenu.isEmpty ? "" : " · hidden: " + offMenu.joined(separator: ", "))")
        lines.append("Theme: \(settings.theme.title)\(settings.theme == .custom ? " (" + settings.customTheme.stamp + ")" : "") · Bookmarks: \(bookmarks.bookmarks.count)")
        let team = agents.team
        let agentsDone = team.jobs.count - team.active.count
        let inChains = team.jobs.filter { $0.chain != nil }.count
        lines.append("Agents: \(team.working.count) working, \(team.queued.count) waiting, \(agentsDone) finished · up to \(settings.agentsAtOnce) at once · in chains: \(inChains)")
        let pinnedReports = reports.library.reports.filter { $0.isPinned }.count
        lines.append("Library: \(reports.library.countLine), \(pinnedReports) pinned · recipes: \(recipes.book.recipes.count)")
        lines.append("Chats saved: \(assistant.chats.book.chats.count)")
        let usedToday = assistant.usage.log.today()
        lines.append("Usage today: \(UsageText.line(usedToday)) · daily cap for agents: \(UsageText.cap(settings.agentDailyCap))")
        let levels = settings.showsLevels ? (settings.levelsAlways ? "on, always showing" : "on") : "off"
        let ownKeys = settings.replacesSystemLevels ? (mediaKeys.isRunning ? "yes" : "wanted, not running") : "no"
        let trusted = DocumentTyper.isTrusted ? "allowed" : "not allowed"
        lines.append("Volume and brightness at the notch: \(levels) · keys taken over: \(ownKeys) · Accessibility: \(trusted)")
        let agentsWeb = settings.agentsUseWeb ? "on" : "off"
        let assistantWeb = assistant.usesWeb ? "on" : "off"
        lines.append("Agents' web: \(agentsWeb) · folders shared with agents: \(settings.agentReadFolders.count) · assistant's web: \(assistantWeb)")
        let work = assignments.assignments
        lines.append("Assignments: \(work.open.count) to hand in, \(work.awaiting.count) waiting for a mark, \(work.marked.count) marked · \(work.subjects.count) subjects")
        lines.append("Add-on files: in this app \(BrowserExtensionInstaller.bundledVersion ?? "missing") · in the folder Chrome loads \(BrowserExtensionInstaller.installedVersion ?? "missing") (\(BrowserExtensionInstaller.installedFolder.path))")
        let lastSync = lastFeedAt.map { MailTime.label(for: $0) } ?? "never"
        if let upload = lastUpload {
            lines.append("Browser add-on \(upload.version ?? "1.0") · whole emails: \(upload.fullEmails ?? "not supported") · last sync \(lastSync)")
        } else {
            lines.append("Browser add-on: not heard from since the app started · mail shown is from \(lastSync)")
        }

        lines.append("")
        lines.append("Accounts:")
        let shown = Set(mailbox.accounts.map { $0.id })
        for (number, feed) in (lastUpload?.feeds ?? []).enumerated() {
            guard let parsed = feed.parsed() else {
                lines.append("\(number + 1). Gmail slot \(feed.index): its feed couldn't be read")
                continue
            }
            let account = parsed.account
            let view = inboxChoice(for: account) == .everything ? "whole inbox" : "Primary + Google mail"
            let how = inboxChoices[account] == nil ? "default" : "chosen"
            let place = mailbox.hidden.contains(account) ? "not in the notch (add it in Mail)" : (shown.contains(account) ? "in the notch" : "no room")
            lines.append("\(number + 1). \(account) · Gmail slot \(feed.index) · \(place) · showing \(view) (\(how))")

            let main = feed.primary == false ? "inbox (no Primary feed)" : "Primary"
            var gmail = "   Gmail: \(main) \(parsed.main.unreadCount) unread, \(parsed.main.entries.count) listed"
            if let inbox = parsed.inbox {
                gmail += " · whole inbox \(inbox.unreadCount) unread, \(inbox.entries.count) listed"
            } else {
                gmail += " · whole inbox not sent"
            }
            lines.append(gmail)
            lines.append("   Feed titles: \(parsed.main.title)" + (parsed.inbox.map { " | \($0.title)" } ?? ""))
            let stats = mailbox.stats(for: account)
            let oldest = stats.oldest.map { " back to \(MailTime.label(for: $0))" } ?? ""
            lines.append("   Notch: \(mailbox.unread[account] ?? 0) unread in Gmail, \(mailbox.shownUnread[account] ?? 0) shown · \(stats.emails) emails kept\(oldest) (\(stats.unread) unread) · whole emails \(stats.whole) fetched, \(stats.failed) failed")
        }
        if lastUpload == nil {
            for account in mailbox.linkedAccounts {
                let stats = mailbox.stats(for: account)
                lines.append("- \(account): \(mailbox.unread[account] ?? 0) unread, \(stats.emails) emails kept (saved copy)")
            }
        }

        lines.append("")
        lines.append("Read in the notch (remembered here, Gmail unchanged): \(mailbox.readHereCount)")
        lines.append("Mail kept on this Mac: \(settings.storage.summary()) · keeping \(settings.wholeEmailLimit == 0 ? "every whole email" : "the newest \(settings.wholeEmailLimit) whole emails")")
        let plan = planner.planner
        let classroomMail = mailbox.messages.filter { ClassroomMail.isClassroom($0.senderEmail) }.count
        lines.append("Planner: \(plan.open().count) to do, \(plan.upcomingExams(now: Date()).count) exams coming · Classroom emails in the notch: \(classroomMail), read into the planner since the app started: \(settings.classroomRead) (reading them is \(settings.classroomHomework ? "on" : "off"))")
        lines.append("Due dates from other emails with the assistant: \(assistant.findsDueDates ? "on · \(settings.finding.summary)" : "off")")
        // Counts only: never what's playing, what was copied or which files.
        let music = NowPlayingWatcher.shared
        lines.append("Extras: now playing \(settings.showsNowPlaying ? "on (\(music.player?.name ?? "no music app open")\(music.problem == nil ? "" : ", not allowed to control it"))" : "off")"
                     + " · focus timer \(settings.showsFocus ? "on" : "off")"
                     + " · clipboard \(settings.keepsClipboard ? "on (\(ClipboardWatcher.shared.list.clips.count) kept in memory)" : "off")"
                     + " · shelf \(settings.showsShelf ? "on (\(shelf.items.count) files)" : "off")"
                     + " · phone battery tool \(PhoneCableWatcher.batteryTool == nil ? "not installed" : "installed")")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ state: Updater.State) -> String {
        switch state {
        case .idle: return "not checked yet"
        case .checking: return "checking"
        case .upToDate: return "up to date"
        case .available(let release): return "build \(release.build) ready to install" + (release.isTest ? " (a test build)" : "")
        case .installing: return "installing"
        case .failed(let message): return "failed (\(message))"
        }
    }

    // MARK: Keeping mail between launches

    /// Shows the mail from the last run straight away, before the add-on's next sync.
    private func restoreMailbox() {
        inboxChoices = AppDelegate.loadInboxChoices()
        if let snapshot = MailboxFile.load() {
            mailbox = LiveMailbox(snapshot: snapshot)
            mailbox.setSavedWhole(emailFiles.ids)
            appliedViews = snapshot.views ?? [:]
            savedRevision = mailbox.revision
            savedViews = appliedViews
            if !snapshot.messages.isEmpty || !snapshot.unread.isEmpty {
                lastFeedAt = snapshot.savedAt
            }
        }
        mailbox.hidden = Set(UserDefaults.standard.stringArray(forKey: AppDelegate.hiddenAccountsKey) ?? [])
        if let met = UserDefaults.standard.stringArray(forKey: AppDelegate.metAccountsKey) {
            metAccounts = Set(met)
        } else {
            // The first run of a build where the notch starts with one inbox: every account
            // linked before now has been met, so what's showing stays as it is.
            metAccounts = Set(mailbox.order)
            metAccounts.formUnion(UserDefaults.standard.stringArray(forKey: AppDelegate.accountOrderKey) ?? [])
            metAccounts.formUnion(inboxChoices.keys)
            metAccounts.formUnion(mailbox.hidden)
            UserDefaults.standard.set(Array(metAccounts).sorted(), forKey: AppDelegate.metAccountsKey)
        }
        measureStorage()
    }

    private func saveMailboxSoon() {
        saveMailboxWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveMailboxNow()
        }
        saveMailboxWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Writes the mailbox to disk if it changed since it was last written (not every
    /// minute). The writing happens off the main thread; `wait` holds on until it's done.
    private func saveMailboxNow(wait: Bool = false) {
        saveMailboxWork?.cancel()
        saveMailboxWork = nil
        if lastFeedAt != nil, mailbox.revision != savedRevision || appliedViews != savedViews {
            let revision = mailbox.revision
            savedRevision = revision
            savedViews = appliedViews
            var snapshot = mailbox.snapshot(at: lastFeedAt ?? Date())
            snapshot.views = appliedViews
            saveQueue.async { [weak self] in
                if let data = MailboxFile.encode(snapshot), MailboxFile.save(data) {
                    return
                }
                // It didn't save: try again at the next chance.
                DispatchQueue.main.async {
                    if self?.savedRevision == revision {
                        self?.savedRevision = -1
                    }
                }
            }
        }
        if wait {
            saveQueue.sync {}
        }
    }

    private func setUpBrowserLink() {
        // Close any open notch first, so it doesn't sit on top of the instructions.
        for model in models where model.level != .rest {
            model.close()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showBrowserLinkSteps()
        }
    }

    /// Puts the add-on's folder in place and shows it in Finder.
    private func showAddOnFolder() {
        if let folder = try? BrowserExtensionInstaller.install() {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
        refreshSettings()
    }

    private func showBrowserLinkSteps() {
        NSApp.activate(ignoringOtherApps: true)
        do {
            let folder = try BrowserExtensionInstaller.install()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(folder.path, forType: .string)
            NSWorkspace.shared.activateFileViewerSelecting([folder])

            let alert = NSAlert()
            alert.messageText = "Link your Gmail"
            alert.informativeText = """
            Use the browser where your Gmail accounts are signed in (Chrome, Arc, Brave or Edge):

            1. Open chrome://extensions (Arc: arc://extensions) and turn on Developer mode.
            2. Drag the highlighted “Notch Inbox Link” folder from Finder onto that page.
               Or click “Load unpacked”, press ⌘⇧G, paste (the folder's path is already copied) and choose it.

            Within a minute, the unread mail of the first Gmail account signed in to that browser shows up in the notch: the Primary tab, plus Google Classroom and other mail from Google. Signed in to more than one? Add the others with “Add an inbox” in Mail, up to three side by side. Your mail only travels from the browser to this app, on this Mac.
            """
            alert.addButton(withTitle: "Done")
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    // MARK: Menu bar

    /// The envelope in the menu bar (often hidden behind the notch) has a short menu:
    /// open the notch, open Settings, quit. Everything else is in Settings.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Notch Inbox")

        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = NSMenuItem(title: "Open Notch Inbox", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Notch Inbox", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        appMenu = menu
        updaterChanged(updater.state)
    }

    /// The notch on the screen you're using: where the pointer is, or the mail tab's screen.
    private func notchNearPointer() -> NotchModel? {
        let mouse = NSEvent.mouseLocation
        let target = screens.values.first(where: { $0.screen.frame.contains(mouse) }) ?? screens.values.first
        return target?.model
    }

    @objc private func openFromMenu() {
        notchNearPointer()?.goHome()
    }

    @objc private func openSettingsFromMenu() {
        notchNearPointer()?.openSettings()
    }

    @objc private func quitFromMenu() {
        quit()
    }

    /// Keeps Settings and every notch's Update button in step with the updater.
    private func updaterChanged(_ state: Updater.State) {
        let build = updater.currentBuild
        settings.build = build
        settings.lastUpdateCheck = updater.lastCheck?.at
        let status: AppSettings.UpdateStatus
        if !updater.canInstall {
            status = .unavailable
        } else {
            switch state {
            case .idle: status = .idle
            case .checking: status = .checking
            case .upToDate: status = .upToDate
            case .available(let release): status = .available(build: release.build, notes: release.notes)
            case .installing: status = .installing
            case .failed(let message): status = .failed(message)
            }
        }
        if settings.update != status {
            settings.update = status
        }

        var pending: Int? = nil
        var isTest = false
        if case .available(let release) = state {
            pending = release.build
            isTest = release.isTest
        }
        if settings.updateIsTest != isTest {
            settings.updateIsTest = isTest
        }
        for model in models {
            model.pendingUpdate = pending
        }

        // After you check for updates, the open notch says how it went.
        switch state {
        case .checking:
            showUpdateNote(userAskedForUpdate ? "Checking for updates…" : nil)
        case .upToDate:
            let upToDate = build > 0 ? "Up to date · Build \(build)" : "Up to date"
            showUpdateNote(userAskedForUpdate ? upToDate : nil, clearAfter: 5)
            userAskedForUpdate = false
        case .failed:
            let failure = lastUpdaterState == .installing ? "Couldn't install the update" : "Couldn't check for updates"
            showUpdateNote(userAskedForUpdate ? failure : nil, clearAfter: 8)
            userAskedForUpdate = false
        case .installing:
            showUpdateNote("Installing update…")
        case .idle, .available:
            showUpdateNote(nil)
            userAskedForUpdate = false
        }
        lastUpdaterState = state
    }

    private func showUpdateNote(_ note: String?, clearAfter seconds: TimeInterval? = nil) {
        clearUpdateNote?.cancel()
        clearUpdateNote = nil
        for model in models where model.updateNote != note {
            model.updateNote = note
        }
        guard note != nil, let seconds = seconds else { return }
        let clear = DispatchWorkItem { [weak self] in
            self?.showUpdateNote(nil)
        }
        clearUpdateNote = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: clear)
    }

    private func checkForUpdates() {
        userAskedForUpdate = true
        updater.check(userInitiated: true)
    }

    private func installUpdate() {
        userAskedForUpdate = true
        updater.install()
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}
