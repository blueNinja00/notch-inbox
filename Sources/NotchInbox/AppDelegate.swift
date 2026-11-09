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
    private var lastSavedMailbox: Data?
    private var saveMailboxWork: DispatchWorkItem?

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
        Assistant.shared.checkSetup()
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
        if updater.canInstall {
            updater.startChecking()
        }

        BrowserExtensionInstaller.refreshIfInstalled()
        browserLink.onFeeds = { [weak self] feeds, upload in
            self?.received(feeds, upload: upload) ?? LinkReply()
        }
        browserLink.onEmail = { [weak self] email in
            self?.received(email)
        }
        browserLink.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveMailboxNow()
        notes.saveNow()
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
        model.minimised = minimised
        model.onMinimise = { [weak self] on in
            self?.setMinimised(on)
        }
        model.notesStore = notes
        model.customSizes = AppDelegate.loadPanelSizes()
        model.onResized = { [weak self] sizes in
            self?.panelResized(sizes)
        }
        model.wholeEmails = wholeEmails
        if lastFeedAt != nil {
            model.showLive(accounts: mailbox.accounts, messages: mailbox.messages, unread: mailbox.shownUnread)
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
        var showing: [GmailFeed] = []
        for account in feeds {
            let choice = inboxChoice(for: account.account)
            if appliedViews[account.account] != choice {
                // Mail kept from a different view isn't mail you read: start this account afresh.
                mailbox.forget(account.account)
                appliedViews[account.account] = choice
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
        let toRead = mailbox.toMarkRead()
        BrowserLink.wantsSync = !toRead.isEmpty
        return LinkReply(want: mailbox.wanted(), addon: addOn, read: toRead)
    }

    /// You opened a real email in the notch: it's read here at once, and in Gmail within
    /// about 30 seconds (the add-on marks it), and its whole text is fetched first.
    private func readInNotch(_ id: String) {
        mailbox.markOpened(id)
        if mailbox.markReadHere(id) {
            BrowserLink.wantsSync = true
            showMailEverywhere()
            saveMailboxSoon()
        }
    }

    /// A whole email (or news that it couldn't be fetched) from the add-on.
    private func received(_ email: EmailUpload) {
        if mailbox.storeWhole(email) {
            showMailEverywhere()
        }
    }

    private func showMailEverywhere() {
        let accounts = mailbox.accounts
        let messages = mailbox.messages
        for model in models {
            model.showLive(accounts: accounts, messages: messages, unread: mailbox.shownUnread)
            if model.wholeEmails != wholeEmails {
                model.wholeEmails = wholeEmails
            }
        }
        refreshMailIcon()
        refreshSettings()
    }

    // MARK: Assistant

    /// What the assistant may know about your day: your newest real emails and latest notes.
    private func assistantContext() -> String {
        var emails: [(account: String, sender: String, subject: String, date: Date, unread: Bool)] = []
        if let model = models.first, !model.isSample {
            let shown = Set(model.accounts.map { $0.id })
            emails = model.messages
                .filter { shown.contains($0.accountID) }
                .sorted { $0.date > $1.date }
                .prefix(20)
                .map { (account: model.account($0.accountID)?.name ?? $0.accountID,
                        sender: $0.sender, subject: $0.subject, date: $0.date, unread: $0.isUnread) }
        }
        let recentNotes = notes.notes
            .filter { !$0.isEmpty }
            .prefix(10)
            .map { (title: $0.title, preview: $0.preview) }
        return AssistantPrompt.context(emails: emails, notes: Array(recentNotes), now: Date())
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

    // MARK: Panel sizes

    private static func loadPanelSizes() -> [NotchLevel: CGSize] {
        let saved = UserDefaults.standard.dictionary(forKey: panelSizesKey) as? [String: [Double]] ?? [:]
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
        settings.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        settings.onInstallUpdate = { [weak self] in
            self?.installUpdate()
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
                                            unread: mailbox.unread, colors: colors)
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
        mailbox.forget(account)
        appliedViews[account] = choice
        mailbox.apply(lastFeeds.filter { $0.account == account }.map { $0.feed(showing: choice) })
        showMailEverywhere()
        saveMailboxSoon()
    }

    private func setHidden(_ hidden: Bool, for account: String) {
        if hidden {
            mailbox.hidden.insert(account)
        } else {
            mailbox.hidden.remove(account)
        }
        UserDefaults.standard.set(Array(mailbox.hidden).sorted(), forKey: AppDelegate.hiddenAccountsKey)
        showMailEverywhere()
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
        var update = "Updates: \(AppDelegate.describe(updater.state))"
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
            let place = mailbox.hidden.contains(account) ? "hidden" : (shown.contains(account) ? "in the notch" : "no room")
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
            lines.append("   Notch: \(mailbox.unread[account] ?? 0) unread · \(stats.emails) emails kept (\(stats.unread) unread) · whole emails \(stats.whole) fetched, \(stats.failed) failed")
        }
        if lastUpload == nil {
            for account in mailbox.linkedAccounts {
                let stats = mailbox.stats(for: account)
                lines.append("- \(account): \(mailbox.unread[account] ?? 0) unread, \(stats.emails) emails kept (saved copy)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ state: Updater.State) -> String {
        switch state {
        case .idle: return "not checked yet"
        case .checking: return "checking"
        case .upToDate: return "up to date"
        case .available(let release): return "build \(release.build) ready to install"
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
            appliedViews = snapshot.views ?? [:]
            var comparable = snapshot
            comparable.savedAt = Date(timeIntervalSince1970: 0)
            lastSavedMailbox = MailboxFile.encode(comparable)
            if !snapshot.messages.isEmpty || !snapshot.unread.isEmpty {
                lastFeedAt = snapshot.savedAt
            }
        }
        mailbox.hidden = Set(UserDefaults.standard.stringArray(forKey: AppDelegate.hiddenAccountsKey) ?? [])
    }

    private func saveMailboxSoon() {
        saveMailboxWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveMailboxNow()
        }
        saveMailboxWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func saveMailboxNow() {
        saveMailboxWork?.cancel()
        saveMailboxWork = nil
        guard lastFeedAt != nil else { return }
        var snapshot = mailbox.snapshot(at: lastFeedAt ?? Date())
        snapshot.views = appliedViews
        // Only rewrite the file when the mail changed, not every minute.
        snapshot.savedAt = Date(timeIntervalSince1970: 0)
        let comparable = MailboxFile.encode(snapshot)
        guard comparable != lastSavedMailbox else { return }
        snapshot.savedAt = lastFeedAt ?? Date()
        if let data = MailboxFile.encode(snapshot), MailboxFile.save(data) {
            lastSavedMailbox = comparable
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

            Within a minute, the unread mail of every Gmail account signed in to that browser shows up in the notch: the Primary tab, plus Google Classroom and other mail from Google. Your mail only travels from the browser to this app, on this Mac.
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
        if case .available(let release) = state {
            pending = release.build
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
