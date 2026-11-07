import AppKit

/// Opens Gmail, and links inside emails, in Google Chrome, where your Gmail accounts are
/// signed in, rather than in the default browser. Without Chrome it tries Arc, Brave and
/// Edge, and only then the default browser.
enum BrowserOpener {
    static let browsers = [
        "com.google.Chrome",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    static func open(_ url: URL) {
        let workspace = NSWorkspace.shared
        let installed = browsers.lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }
        guard let browser = installed.first else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
