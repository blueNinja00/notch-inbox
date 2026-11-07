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

    /// One notch per connected screen, keyed by display.
    private var screens: [CGDirectDisplayID: NotchWindowController] = [:]
    private var levelWatchers: [CGDirectDisplayID: AnyCancellable] = [:]
    private var screenObserver: NSObjectProtocol?

    private let updater = Updater()
    private let browserLink = BrowserLink()
    private var mailbox = LiveMailbox(order: UserDefaults.standard.stringArray(forKey: AppDelegate.accountOrderKey) ?? [])
    private var lastFeedAt: Date?

    private var statusItem: NSStatusItem?
    private var appMenu: NSMenu?
    private var versionItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var linkItem: NSMenuItem?
    /// "Open Inboxes" and its divider, hidden when the menu opens from inside the notch.
    private var menuBarOnlyItems: [NSMenuItem] = []
    private var subscriptions = Set<AnyCancellable>()

    /// Set when you ask for an update check or install, so the notch can say how it went.
    private var userAskedForUpdate = false
    private var lastUpdaterState: Updater.State = .idle
    private var clearUpdateNote: DispatchWorkItem?

    private var models: [NotchModel] { screens.values.map { $0.model } }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        browserLink.onFeeds = { [weak self] feeds in
            self?.received(feeds)
        }
        browserLink.start()
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

    private func received(_ feeds: [GmailFeed]) {
        guard !feeds.isEmpty else { return }
        mailbox.apply(feeds)
        UserDefaults.standard.set(mailbox.order, forKey: AppDelegate.accountOrderKey)
        let accounts = mailbox.accounts
        let messages = mailbox.messages
        for model in models {
            model.showLive(accounts: accounts, messages: messages, unread: mailbox.unread)
        }
        lastFeedAt = Date()
        refreshLinkItem()
    }

    private func refreshLinkItem() {
        guard let item = linkItem else { return }
        guard let last = lastFeedAt else {
            item.title = "Gmail: not linked yet"
            return
        }
        let count = mailbox.accounts.count
        let accounts = "\(count) account\(count == 1 ? "" : "s")"
        if Date().timeIntervalSince(last) > 5 * 60 {
            item.title = "Gmail link paused · last update \(MailTime.label(for: last))"
        } else {
            item.title = "Gmail linked · \(accounts) · updated \(MailTime.label(for: last))"
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

            Within a minute, the unread Primary mail of every Gmail account signed in to that browser shows up in the notch. Your mail only travels from the browser to this app, on this Mac.
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

    func menuWillOpen(_ menu: NSMenu) {
        refreshLinkItem()
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
        updater.check()
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
