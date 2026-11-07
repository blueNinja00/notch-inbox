import AppKit
import Combine

/// Checks GitHub for a newer build every couple of minutes and, when you say so, installs
/// it and relaunches. Every push to the repository's main branch publishes a numbered build.
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing
        case failed(String)
    }

    static let repository = "blueNinja00/notch-inbox"
    static let assetName = "NotchInbox.zip"
    /// Cheap: GitHub answers "nothing new" (304) to a repeat question, which doesn't count
    /// towards its hourly limit.
    private static let checkInterval: TimeInterval = 2 * 60

    @Published private(set) var state: State = .idle

    /// Build number stamped into the app by the release workflow; 0 for local builds.
    let currentBuild: Int

    private var timer: Timer?
    private var isChecking = false
    /// The newest release seen and GitHub's tag for that answer, to ask "anything newer?".
    private var latestSeen: ReleaseInfo?
    private var etag: String?

    init(bundle: Bundle = .main) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        currentBuild = Int(version ?? "") ?? 0
    }

    /// Only the packaged .app can swap itself for a newer copy (not `swift run`).
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = state { return release }
        return nil
    }

    func startChecking() {
        check()
        let timer = Timer(timeInterval: Updater.checkInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Checking

    /// Background checks stay quiet: no "Checking…", and a failed one (offline, say) keeps
    /// what was known. Checks you ask for show their progress and any error.
    func check(userInitiated: Bool = false) {
        guard !isChecking, state != .installing else { return }
        guard let url = URL(string: "https://api.github.com/repos/\(Updater.repository)/releases/latest") else { return }
        isChecking = true
        if userInitiated {
            state = .checking
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchInbox/\(currentBuild)", forHTTPHeaderField: "User-Agent")
        if let etag = etag, latestSeen != nil {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let tag = http?.value(forHTTPHeaderField: "ETag")
            let release = data.flatMap { ReleaseFeed.parse($0, assetName: Updater.assetName) }
            DispatchQueue.main.async {
                self?.finishCheck(release: release, status: status, etag: tag, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func finishCheck(release: ReleaseInfo?, status: Int, etag: String?, error: Error?, userInitiated: Bool) {
        isChecking = false
        if status == 304, let known = latestSeen {
            settle(known.build > currentBuild ? .available(known) : .upToDate)
        } else if let release = release {
            latestSeen = release
            self.etag = etag
            settle(release.build > currentBuild ? .available(release) : .upToDate)
        } else if status == 404 {
            settle(.upToDate) // nothing published yet
        } else if userInitiated || state == .checking {
            state = .failed(error?.localizedDescription ?? "Couldn't check GitHub for updates.")
        }
    }

    /// Announces a state only when it changed, so the menu and notch don't redraw every check.
    private func settle(_ new: State) {
        if state != new {
            state = new
        }
    }

    // MARK: Installing

    func install() {
        guard let release = availableRelease else { return }
        guard canInstall else {
            state = .failed("Updates install into “Notch Inbox.app”. Open the app rather than using swift run.")
            return
        }

        let appURL = Bundle.main.bundleURL
        let workFolder: URL
        do {
            // A scratch folder on the same disk as the app, so the swap is a quick rename.
            workFolder = try FileManager.default.url(for: .itemReplacementDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: appURL,
                                                     create: true)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        state = .installing
        URLSession.shared.downloadTask(with: release.downloadURL) { [weak self] tempURL, response, error in
            // The downloaded file is deleted when this callback returns, so move it first.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            var outcome: Result<URL, Error>
            if let tempURL = tempURL, status < 400 {
                let zip = workFolder.appendingPathComponent(Updater.assetName)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: zip)
                    outcome = .success(zip)
                } catch {
                    outcome = .failure(error)
                }
            } else {
                outcome = .failure(error ?? UpdateError("The download failed (HTTP \(status))."))
            }
            DispatchQueue.main.async {
                self?.finishInstall(outcome, replacing: appURL, workFolder: workFolder)
            }
        }.resume()
    }

    private func finishInstall(_ download: Result<URL, Error>, replacing appURL: URL, workFolder: URL) {
        do {
            let zip = try download.get()
            try Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, workFolder.path])
            let items = try FileManager.default.contentsOfDirectory(at: workFolder, includingPropertiesForKeys: nil)
            guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError("The download didn't contain the app.")
            }
            let installed = try FileManager.default.replaceItemAt(appURL, withItemAt: newApp) ?? appURL
            try? FileManager.default.removeItem(at: workFolder)
            Updater.relaunch(installed)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw UpdateError("Couldn't unpack the update.")
        }
    }

    /// Opens the new copy a moment after this one quits.
    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

struct UpdateError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
