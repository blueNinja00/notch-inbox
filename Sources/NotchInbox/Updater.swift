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
    private static let checkInterval: TimeInterval = 2 * 60

    @Published private(set) var state: State = .idle

    /// Build number stamped into the app by the release workflow; 0 for local builds.
    let currentBuild: Int
    /// github.com, and GitHub's API (other addresses in tests).
    private let site: URL
    private let api: URL

    private var timer: Timer?
    private var isChecking = false
    /// The newest release seen, with its notes and download links.
    private var latestSeen: ReleaseInfo?
    /// When GitHub was last asked, and what it said, for Copy Debug Info.
    private(set) var lastCheck: (at: Date, result: String)?

    init(bundle: Bundle = .main,
         site: URL = URL(string: "https://github.com")!,
         api: URL = URL(string: "https://api.github.com")!) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        currentBuild = Int(version ?? "") ?? 0
        self.site = site
        self.api = api
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

    /// Asks github.com which build is newest: its "latest release" link sends you on to that
    /// build's page (".../releases/tag/build-25"), so a quick look at where it leads is enough.
    /// Not GitHub's API: that allows an app that isn't signed in 60 questions an hour from your
    /// network, shared with every other app on it (and with everyone behind a school's or an
    /// internet provider's shared address), and counts every one, even "anything new?". If
    /// github.com doesn't say, the API is asked instead.
    ///
    /// Background checks stay quiet: no "Checking…", and a failed one (offline, say) keeps
    /// what was known. Checks you ask for show their progress and say why one failed.
    func check(userInitiated: Bool = false) {
        guard !isChecking, state != .installing else { return }
        isChecking = true
        if userInitiated {
            state = .checking
        }

        var request = URLRequest(url: site.appendingPathComponent("\(Updater.repository)/releases/latest"))
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("NotchInbox/\(currentBuild)", forHTTPHeaderField: "User-Agent")
        let site = self.site
        URLSession.shared.dataTask(with: request) { [self] _, response, error in
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let build = status == 200
                ? http?.url.flatMap { ReleaseFeed.buildNumber(fromPage: $0, site: site, repository: Updater.repository) }
                : nil
            let said = "github.com: " + (error?.localizedDescription
                ?? "HTTP \(status)" + (build.map { ", newest is build \($0)" } ?? ""))
            DispatchQueue.main.async {
                if let build = build {
                    self.newest(build, said: said)
                } else {
                    self.askAPI(after: said, userInitiated: userInitiated)
                }
            }
        }.resume()
    }

    /// github.com named the newest build. If it's newer than this one, GitHub's API is asked
    /// for its notes and API download link: one question per new build. If the API doesn't
    /// answer, the usual download link will do.
    private func newest(_ build: Int, said: String) {
        guard build > currentBuild else {
            finishCheck(.upToDate, said: said)
            return
        }
        if let seen = latestSeen, seen.build == build {
            finishCheck(.available(seen), said: said)
            return
        }
        let plain = ReleaseFeed.release(build: build, site: site, repository: Updater.repository, assetName: Updater.assetName)
        let url = api.appendingPathComponent("repos/\(Updater.repository)/releases/tags/build-\(build)")
        URLSession.shared.dataTask(with: apiRequest(url)) { [self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let found = data.flatMap { ReleaseFeed.parse($0, assetName: Updater.assetName) }
            DispatchQueue.main.async {
                let release = found.flatMap { $0.build == build ? $0 : nil } ?? plain
                self.latestSeen = release
                self.finishCheck(.available(release), said: said + "; its notes from the API: " + (found == nil ? "HTTP \(status), none" : "found"))
            }
        }.resume()
    }

    /// github.com didn't say: GitHub's API, the way earlier builds asked.
    private func askAPI(after said: String, userInitiated: Bool) {
        let url = api.appendingPathComponent("repos/\(Updater.repository)/releases/latest")
        URLSession.shared.dataTask(with: apiRequest(url)) { [self] data, response, error in
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let release = data.flatMap { ReleaseFeed.parse($0, assetName: Updater.assetName) }
            let problem = ReleaseFeed.problem(status: status, error: error,
                                              remaining: http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                                              reset: http?.value(forHTTPHeaderField: "X-RateLimit-Reset"))
            let both = said + "; API: " + (error?.localizedDescription
                ?? "HTTP \(status)" + (release.map { ", newest is build \($0.build)" } ?? ""))
            DispatchQueue.main.async {
                if let release = release {
                    self.latestSeen = release
                    self.finishCheck(release.build > self.currentBuild ? .available(release) : .upToDate, said: both)
                } else if status == 404 {
                    self.finishCheck(.upToDate, said: both) // nothing published yet
                } else {
                    self.failCheck("Couldn't check for updates: \(problem)", said: both, userInitiated: userInitiated)
                }
            }
        }.resume()
    }

    private func apiRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchInbox/\(currentBuild)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func finishCheck(_ new: State, said: String) {
        isChecking = false
        lastCheck = (Date(), said)
        settle(new)
    }

    private func failCheck(_ problem: String, said: String, userInitiated: Bool) {
        isChecking = false
        lastCheck = (Date(), "failed: \(said)")
        if userInitiated || state == .checking {
            state = .failed(problem)
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
            state = .failed("Couldn't install the update: updates install into “Notch Inbox.app”. Open the app rather than using swift run.")
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
            state = .failed("Couldn't install the update: \(error.localizedDescription)")
            return
        }

        state = .installing
        download(release.downloadURLs, into: workFolder, attempt: 1) { [weak self] outcome in
            self?.finishInstall(outcome, replacing: appURL, workFolder: workFolder)
        }
    }

    /// GitHub sometimes answers a download with a server error (502, 503, 504) or drops the
    /// connection. So it tries GitHub's API route first, then the usual link, each up to
    /// three times, waiting a little longer each time, before saying it failed.
    private func download(_ urls: [URL], into workFolder: URL, attempt: Int, done: @escaping (Result<URL, Error>) -> Void) {
        guard let url = urls.first else {
            DispatchQueue.main.async { done(.failure(UpdateError("There was nothing to download."))) }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if url.host == "api.github.com" {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }
        URLSession.shared.downloadTask(with: request) { [self] tempURL, response, error in
            // The downloaded file is deleted when this callback returns, so move it first.
            let status = (response as? HTTPURLResponse)?.statusCode ?? (error == nil ? 200 : 0)
            if let tempURL = tempURL, error == nil, status < 400 {
                let zip = workFolder.appendingPathComponent(Updater.assetName)
                let outcome: Result<URL, Error>
                do {
                    try? FileManager.default.removeItem(at: zip)
                    try FileManager.default.moveItem(at: tempURL, to: zip)
                    outcome = .success(zip)
                } catch {
                    outcome = .failure(error)
                }
                DispatchQueue.main.async { done(outcome) }
                return
            }
            let passing = status >= 500 || status == 429 || status == 0
            if passing && attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt * 3)) {
                    self.download(urls, into: workFolder, attempt: attempt + 1, done: done)
                }
                return
            }
            if urls.count > 1 {
                // This route isn't working: the next one, fresh.
                self.download(Array(urls.dropFirst()), into: workFolder, attempt: 1, done: done)
                return
            }
            let failure = error ?? UpdateError(passing
                ? "GitHub didn't answer (HTTP \(status)) after 3 tries. Try Install again in a minute."
                : "The download failed (HTTP \(status)).")
            DispatchQueue.main.async { done(.failure(failure)) }
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
            state = .failed("Couldn't install the update: \(error.localizedDescription)")
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

    /// Opens the new copy once this one has quit. (Opening it while this copy is still
    /// quitting would just bring this one forward.)
    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c",
                             "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                             app.path,
                             String(ProcessInfo.processInfo.processIdentifier)]
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
