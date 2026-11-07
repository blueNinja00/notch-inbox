import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Menu-bar-only app: no Dock icon and no app menu. The notch panel and a
    /// small envelope menu in the menu bar (updates, Quit) are created at launch.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private var model: NotchModel?
    private var controller: NotchWindowController?
    private let updater = Updater()
    private var statusItem: NSStatusItem?
    private var versionItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let placement = NotchPlacement.detect() else { return }

        // Swap SampleMailProvider for a real provider once accounts are connected.
        let model = NotchModel(provider: SampleMailProvider(), metrics: placement.metrics)
        let controller = NotchWindowController(model: model, screen: placement.screen)
        controller.show()
        self.model = model
        self.controller = controller

        installStatusItem()

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
    }

    /// The app has no Dock icon, so a small menu-bar item handles updates and quitting.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Notch Inbox")

        let menu = NSMenu()
        menu.autoenablesItems = false

        let version = NSMenuItem(title: "Notch Inbox", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let update = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
        update.target = self
        menu.addItem(update)
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
        updaterChanged(updater.state)
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
