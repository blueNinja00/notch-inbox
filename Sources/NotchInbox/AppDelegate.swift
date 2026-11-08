import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Menu-bar-only app: no Dock icon and no app menu. A notch panel per screen and the
    /// app menu (Gmail link, updates, Quit) are created at launch. The menu opens from the
    /// envelope in the menu bar and from the menu button inside the open notch.
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
    /// Choices you made in the menu. (Version 2: build 5's automatic guesses are dropped.)
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
    private var appMenu: NSMenu?
    private var versionItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var linkItem: NSMenuItem?
    /// One item per linked account, with its choices, rebuilt each time the menu opens.
    private var accountItems: [NSMenuItem] = []
    /// "Open Inboxes" and its divider, hidden when the menu opens from inside the notch.
    private var menuBarOnlyItems: [NSMenuItem] = []
    private var subscriptions = Set<AnyCancellable>()

    /// Set when you ask for an update check or install, so the notch can say how it went.
    private var userAskedForUpdate = false
    private var lastUpdaterState: Updater.State = .idle
    private var clearUpdateNote: DispatchWorkItem?

    private var models: [NotchModel] { screens.values.map { $0.model } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreMailbox()
        installStatusItem()

        syncScreens()
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
        model.onShowAppMenu = { [weak self] in
            self?.showAppMenuAtPointer()
        }
        model.onOpenMessage = { [weak self] id in
            self?.mailbox.markOpened(id)
        }
        model.wholeEmails = wholeEmails
        if lastFeedAt != nil {
            model.showLive(accounts: mailbox.accounts, messages: mailbox.messages, unread: mailbox.unread)
        }
        model.pendingUpdate = updater.availableRelease?.build
        return model
    }

    /// Only one notch is open at a time: opening one closes any other.
    private func panelLevelChanged(_ level: NotchLevel, on id: CGDirectDisplayID) {
        guard level == .lanes || level == .detail else { return }
        for (other, controller) in screens where other != id && controller.model.level != .rest {
            controller.model.close()
        }
    }

    // MARK: Gmail via the browser add-on

    /// Each minute's feeds. The answer asks the add-on for the whole emails still missing.
    private func received(_ feeds: [AccountFeeds], upload: FeedUpload) -> LinkReply {
        let addOn = BrowserExtensionInstaller.bundledVersion
        lastUpload = upload
        guard !feeds.isEmpty else { return LinkReply(want: [], addon: addOn) }
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
        refreshLinkItem()
        saveMailboxSoon()
        return LinkReply(want: mailbox.wanted(), addon: addOn)
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
            model.showLive(accounts: accounts, messages: messages, unread: mailbox.unread)
            if model.wholeEmails != wholeEmails {
                model.wholeEmails = wholeEmails
            }
        }
    }

    private func refreshLinkItem() {
        guard let item = linkItem else { return }
        guard let last = lastFeedAt else {
            item.title = "Gmail: not linked yet"
            return
        }
        let count = mailbox.linkedAccounts.count
        let accounts = "\(count) account\(count == 1 ? "" : "s")"
        if Date().timeIntervalSince(last) > 5 * 60 {
            item.title = "Gmail link paused · last update \(MailTime.label(for: last))"
        } else if wholeEmails == .addOnNeedsReload {
            item.title = "Gmail linked · reload the add-on in Chrome to finish updating"
        } else {
            item.title = "Gmail linked · \(accounts) · updated \(MailTime.label(for: last))"
        }
    }

    // MARK: Accounts in the menu

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

    /// Under the Gmail line: each linked account, with what the notch shows of it.
    private func rebuildAccountItems() {
        guard let menu = appMenu, let link = linkItem else { return }
        accountItems.forEach { menu.removeItem($0) }
        accountItems = []

        let shown = Set(mailbox.accounts.map { $0.id })
        var position = menu.index(of: link) + 1
        for account in mailbox.linkedAccounts {
            let choice = inboxChoice(for: account)
            let isHidden = mailbox.hidden.contains(account)
            let summary: String
            if isHidden {
                summary = "hidden"
            } else if !shown.contains(account) {
                summary = "no room"
            } else {
                summary = choice == .everything ? "whole inbox" : "Primary"
            }

            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.addItem(choiceItem("Primary tab, plus Classroom and other Google mail", .primary, account, current: choice))
            submenu.addItem(choiceItem("Whole inbox (every tab)", .everything, account, current: choice))
            submenu.addItem(NSMenuItem.separator())
            let show = NSMenuItem(title: "Show in the Notch", action: #selector(toggleAccountShown(_:)), keyEquivalent: "")
            show.target = self
            show.representedObject = account
            show.state = isHidden ? .off : .on
            submenu.addItem(show)
            if !isHidden && !shown.contains(account) {
                let room = NSMenuItem(title: "The notch has room for three accounts. Hide one to show this one.",
                                      action: nil, keyEquivalent: "")
                room.isEnabled = false
                submenu.addItem(room)
            }

            let item = NSMenuItem(title: "\(account) · \(summary)", action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.insertItem(item, at: position)
            position += 1
            accountItems.append(item)
        }
    }

    private func choiceItem(_ title: String, _ choice: InboxChoice, _ account: String, current: InboxChoice) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(chooseInbox(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = "\(choice.rawValue) \(account)"
        item.state = choice == current ? .on : .off
        return item
    }

    @objc private func chooseInbox(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let space = value.firstIndex(of: " "),
              let choice = InboxChoice(rawValue: String(value[..<space])) else { return }
        let account = String(value[value.index(after: space)...])
        let before = inboxChoice(for: account)
        inboxChoices[account] = choice
        saveInboxChoices()
        guard choice != before else { return }
        // Swap the account's mail straight away from the latest feeds.
        mailbox.forget(account)
        appliedViews[account] = choice
        mailbox.apply(lastFeeds.filter { $0.account == account }.map { $0.feed(showing: choice) })
        showMailEverywhere()
        saveMailboxSoon()
    }

    @objc private func toggleAccountShown(_ sender: NSMenuItem) {
        guard let account = sender.representedObject as? String else { return }
        if mailbox.hidden.contains(account) {
            mailbox.hidden.remove(account)
        } else {
            mailbox.hidden.insert(account)
        }
        UserDefaults.standard.set(Array(mailbox.hidden).sorted(), forKey: AppDelegate.hiddenAccountsKey)
        showMailEverywhere()
    }

    // MARK: Debugging

    /// Copies a plain report of what the app and the browser add-on are doing: builds,
    /// update checks, and per account what Gmail's feeds say and what the notch holds.
    /// Counts and addresses only, no email contents.
    @objc private func copyDebugInfo() {
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

    @objc private func setUpBrowserLink() {
        // Close any open notch first, so it doesn't sit on top of the instructions.
        for model in models where model.level != .rest {
            model.close()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showBrowserLinkSteps()
        }
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

    // MARK: App menu

    /// The app has no Dock icon, so its menu (Gmail link, updates, Quit) lives in the menu
    /// bar's envelope and behind the menu button in the open notch.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Notch Inbox")

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let version = NSMenuItem(title: "Notch Inbox", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let update = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(NSMenuItem.separator())

        let link = NSMenuItem(title: "Gmail: not linked yet", action: nil, keyEquivalent: "")
        link.isEnabled = false
        menu.addItem(link)

        let setUp = NSMenuItem(title: "Set Up Browser Link…", action: #selector(setUpBrowserLink), keyEquivalent: "")
        setUp.target = self
        menu.addItem(setUp)
        let debug = NSMenuItem(title: "Copy Debug Info", action: #selector(copyDebugInfo), keyEquivalent: "")
        debug.target = self
        menu.addItem(debug)
        menu.addItem(NSMenuItem.separator())

        let open = NSMenuItem(title: "Open Inboxes", action: #selector(openInboxes), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let openDivider = NSMenuItem.separator()
        menu.addItem(openDivider)

        let quit = NSMenuItem(title: "Quit Notch Inbox", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        appMenu = menu
        versionItem = version
        updateItem = update
        linkItem = link
        menuBarOnlyItems = [open, openDivider]
        updaterChanged(updater.state)
        refreshLinkItem()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === appMenu else { return }
        refreshLinkItem()
        rebuildAccountItems()
    }

    /// The menu button inside the notch opens the same menu where you clicked.
    private func showAppMenuAtPointer() {
        guard let menu = appMenu else { return }
        let point = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.menuBarOnlyItems.forEach { $0.isHidden = true }
            _ = menu.popUp(positioning: nil, at: point, in: nil)
            self.menuBarOnlyItems.forEach { $0.isHidden = false }
        }
    }

    /// Keeps the menu and every notch's Update button in step with the updater.
    private func updaterChanged(_ state: Updater.State) {
        let build = updater.currentBuild
        versionItem?.title = build > 0 ? "Notch Inbox · Build \(build)" : "Notch Inbox · local build"
        updateItem?.toolTip = nil

        switch state {
        case .idle:
            setUpdateItem("Check for Updates…", action: #selector(checkForUpdates))
        case .checking:
            setUpdateItem("Checking for Updates…", action: nil)
        case .upToDate:
            setUpdateItem("Check for Updates…", action: #selector(checkForUpdates))
            if build > 0 {
                versionItem?.title = "Notch Inbox · Build \(build) · up to date"
            }
        case .available(let release):
            setUpdateItem("Install Update (Build \(release.build))", action: #selector(installUpdate))
            updateItem?.toolTip = release.notes.isEmpty ? nil : release.notes
        case .installing:
            setUpdateItem("Installing Update…", action: nil)
        case .failed(let message):
            setUpdateItem("Couldn't Update — Try Again", action: #selector(checkForUpdates))
            updateItem?.toolTip = message
        }

        if !updater.canInstall {
            setUpdateItem("Updates work in the installed app", action: nil)
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

    private func setUpdateItem(_ title: String, action: Selector?) {
        updateItem?.title = title
        updateItem?.action = action
        updateItem?.isEnabled = action != nil
    }

    @objc private func checkForUpdates() {
        userAskedForUpdate = true
        updater.check(userInitiated: true)
    }

    @objc private func installUpdate() {
        userAskedForUpdate = true
        updater.install()
    }

    /// Opens the notch on the screen you clicked the menu on.
    @objc private func openInboxes() {
        let mouse = NSEvent.mouseLocation
        let target = screens.values.first(where: { $0.screen.frame.contains(mouse) }) ?? screens.values.first
        target?.model.openLanes()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
