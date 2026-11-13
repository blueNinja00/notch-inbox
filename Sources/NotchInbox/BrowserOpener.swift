import AppKit

/// Opens Gmail, and links inside emails, in Google Chrome, where your Gmail accounts are
/// signed in, rather than in the default browser. Without Chrome it tries Arc, Brave and
/// Edge, and only then the default browser. A page that belongs with one of your inboxes
/// opens in the browser profile that inbox is signed in to.
enum BrowserOpener {
    static let browsers = [
        "com.google.Chrome",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    /// The first of those that's installed: which it is, and where.
    static func installed() -> (id: String, app: URL)? {
        let workspace = NSWorkspace.shared
        for id in browsers {
            if let app = workspace.urlForApplication(withBundleIdentifier: id) {
                return (id, app)
            }
        }
        return nil
    }

    /// Opens a page in whichever of the browser's windows is in front.
    static func open(_ url: URL) {
        let workspace = NSWorkspace.shared
        guard let browser = installed() else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: browser.app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: Profiles

    /// Where a browser keeps its profiles, if it keeps them the way Chrome does.
    static func profileFolder(for browser: String) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return BrowserProfiles.dataFolder(for: browser, support: support)
    }

    /// The browser's files are read here, off the main thread.
    private static let reading = DispatchQueue(label: "notch-inbox.browser-profiles", qos: .userInitiated)

    /// Reads the browser's profiles and hands them back on the main thread, with the
    /// browser's name ("Google Chrome"). No browser that keeps profiles gives "" and none.
    static func readProfiles(then done: @escaping (_ browser: String, _ profiles: [BrowserProfile]) -> Void) {
        guard let browser = installed(), let folder = profileFolder(for: browser.id) else {
            done("", [])
            return
        }
        let name = FileManager.default.displayName(atPath: browser.app.path).replacingOccurrences(of: ".app", with: "")
        reading.async {
            let profiles = BrowserProfiles.read(folder: folder)
            DispatchQueue.main.async {
                done(name, profiles)
            }
        }
    }

    /// Opens a page that belongs with one of your inboxes in the browser profile that
    /// goes with it: the one you picked for that inbox, or the one its address is signed
    /// in to. With nothing to go on (one profile only, none that fits, or a browser that
    /// doesn't keep profiles this way), it opens in the window in front, as before.
    /// `seen` is handed the profiles that were read, for Settings.
    static func open(_ url: URL, account: String, place: LinkPlace, seen: @escaping (_ browser: String, _ profiles: [BrowserProfile]) -> Void) {
        guard place != .front, let browser = installed() else {
            open(url)
            return
        }
        readProfiles { name, profiles in
            seen(name, profiles)
            guard profiles.count > 1,
                  let target = BrowserProfiles.target(for: account, place: place, in: profiles),
                  let arguments = BrowserProfiles.arguments(for: url, directory: target.directory) else {
                open(url)
                return
            }
            // A second copy of the browser is started with the profile and the page. If the
            // browser is already running, it takes them over and the second copy quits.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: browser.app, configuration: configuration) { _, error in
                if error != nil {
                    DispatchQueue.main.async {
                        open(url)
                    }
                }
            }
        }
    }
}
