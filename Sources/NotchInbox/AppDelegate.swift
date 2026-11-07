import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Menu-bar-only app: no Dock icon and no app menu. The notch panel and a
    /// small envelope menu in the menu bar (Gmail link, updates, Quit) are created at launch.
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

    private var model: NotchModel?
    private var controller: NotchWindowController?
    private let updater = Updater()
    private let browserLink = BrowserLink()
    private var mailbox = LiveMailbox(order: UserDefaults.standard.stringArray(forKey: AppDelegate.accountOrderKey) ?? [])
    private var lastFeedAt: Date?

    private var statusItem: NSStatusItem?
    private var versionItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var linkItem: NSMenuItem?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let placement = NotchPlacement.detect() else { return }

        // Sample mail until the browser add-on delivers your Gmail.
        let model = NotchModel(provider: SampleMailProvider(), metrics: placement.metrics)
        let controller = NotchWindowController(model: model, screen: placement.screen)
        controller.show()
        self.model = model
        self.controller = controller

        installStatusItem()

        model.onOpenURL = { url in
            NSWorkspace.shared.open(url)
        }
        model.onInstallUpdate = { [weak self] in
            self?.updater.install()
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

    // MARK: Gmail via the browser add-on

    private func received(_ feeds: [GmailFeed]) {
        guard !feeds.isEmpty else { return }
        mailbox.apply(feeds)
        UserDefaults.standard.set(mailbox.order, forKey: AppDelegate.accountOrderKey)
        model?.showLive(accounts: mailbox.accounts, messages: mailbox.messages, unread: mailbox.unread)
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

    // MARK: Menu bar

    /// The app has no Dock icon, so a small menu-bar item holds the Gmail link, updates and Quit.
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
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit Notch Inbox", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        versionItem = version
        updateItem = update
        linkItem = link
        updaterChanged(updater.state)
        refreshLinkItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLinkItem()
    }

    /// Keeps the menu and the notch's Update button in step with the updater.
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

        if case .available(let release) = state {
            model?.pendingUpdate = release.build
        } else {
            model?.pendingUpdate = nil
        }
    }

    private func setUpdateItem(_ title: String, action: Selector?) {
        updateItem?.title = title
        updateItem?.action = action
        updateItem?.isEnabled = action != nil
    }

    @objc private func checkForUpdates() {
        updater.check()
    }

    @objc private func installUpdate() {
        updater.install()
    }

    @objc private func openInboxes() {
        model?.openLanes()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
