import Foundation

/// A build published on the repository's GitHub Releases page.
struct ReleaseInfo: Equatable {
    let build: Int
    let notes: String
    let downloadURL: URL
    /// The same file through GitHub's API (asked for with "Accept: application/octet-stream").
    /// It goes straight to GitHub's file servers, and kept working when the usual link
    /// answered 504.
    var apiURL: URL? = nil
    /// A test build: published, but not released to everyone yet. Only copies with
    /// "Get test builds" switched on are offered it.
    var isTest = false

    /// Where to download from, in order.
    var downloadURLs: [URL] {
        [apiURL, downloadURL].compactMap { $0 }
    }
}

/// Reads GitHub's "latest release" response. Release tags look like "build-12",
/// and the number matches the app's CFBundleVersion.
enum ReleaseFeed {
    private struct Response: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            let url: URL?
        }

        let tagName: String
        let body: String?
        let assets: [Asset]
    }

    static func parse(_ data: Data, assetName: String) -> ReleaseInfo? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data),
              let build = buildNumber(from: response.tagName),
              let asset = response.assets.first(where: { $0.name == assetName }) else {
            return nil
        }
        let api = asset.url.flatMap { $0.host == "api.github.com" ? $0 : nil }
        return ReleaseInfo(build: build, notes: response.body ?? "", downloadURL: asset.browserDownloadUrl, apiURL: api)
    }

    static func buildNumber(from tag: String) -> Int? {
        Int(tag.drop(while: { !$0.isNumber }))
    }

    /// The build a release's page on github.com is for: ".../owner/repo/releases/tag/build-25"
    /// gives 25. Anything else (a sign-in page, a network's own page) gives nil.
    static func buildNumber(fromPage url: URL, site: URL, repository: String) -> Int? {
        guard url.host?.lowercased() == site.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        let expected = repository.lowercased().split(separator: "/").map(String.init) + ["releases", "tag"]
        guard parts.count == expected.count + 1, Array(parts.prefix(expected.count)) == expected,
              let tag = parts.last, tag.hasPrefix("build-") else { return nil }
        return buildNumber(from: tag)
    }

    /// A build named on github.com, with its usual download link (no notes).
    static func release(build: Int, site: URL, repository: String, assetName: String, isTest: Bool = false) -> ReleaseInfo {
        let link = site.appendingPathComponent("\(repository)/releases/download/build-\(build)/\(assetName)")
        return ReleaseInfo(build: build, notes: "", downloadURL: link, isTest: isTest)
    }

    // MARK: Test builds

    /// The first build that knows about test builds. Builds before it can't be released
    /// to everyone again: a copy of one would be offered every build as it's pushed.
    static let firstWithTestBuilds = 43

    /// A build's own page on github.com. Every published build has one, whether or not
    /// it has been released to everyone, so it says whether a build exists.
    static func page(build: Int, site: URL, repository: String) -> URL {
        site.appendingPathComponent("\(repository)/releases/tag/build-\(build)")
    }

    /// Where a build is released to everyone: the "Release to everyone" page of the
    /// repository's Actions, which only its owner can run.
    static func releasePage(site: URL, repository: String) -> URL {
        site.appendingPathComponent("\(repository)/actions/workflows/promote.yml")
    }

    private struct Listed: Decodable {
        struct Asset: Decodable {
            let name: String
        }

        let tagName: String
        let draft: Bool?
        let assets: [Asset]?
    }

    /// The newest build in GitHub's list of releases (from its API), test builds included:
    /// the highest-numbered one that's published and has the app attached.
    static func newestListed(_ data: Data, assetName: String) -> Int? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let list = try? decoder.decode([Listed].self, from: data) else { return nil }
        let builds = list.compactMap { entry -> Int? in
            guard entry.draft != true, entry.tagName.hasPrefix("build-"),
                  (entry.assets ?? []).contains(where: { $0.name == assetName }) else { return nil }
            return buildNumber(from: entry.tagName)
        }
        return builds.max()
    }

    private struct Runs: Decodable {
        struct Run: Decodable {
            let runNumber: Int
            let conclusion: String?
        }

        let workflowRuns: [Run]
    }

    /// The newest build there is, from GitHub's list of the times the "Build and release"
    /// workflow has run: a build's number is the number of the run that made it. (GitHub's
    /// list of releases isn't in date order, so the newest build can be far down it.)
    static func newestRun(_ data: Data) -> Int? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let runs = try? decoder.decode(Runs.self, from: data) else { return nil }
        return runs.workflowRuns.filter { $0.conclusion == "success" && $0.runNumber > 0 }.map { $0.runNumber }.max()
    }

    /// Where that list is asked for: the newest run that succeeded.
    static func runsAddress(api: URL, repository: String) -> URL? {
        var address = URLComponents(url: api.appendingPathComponent("repos/\(repository)/actions/workflows/release.yml/runs"), resolvingAgainstBaseURL: false)
        address?.queryItems = [URLQueryItem(name: "per_page", value: "1"), URLQueryItem(name: "status", value: "success")]
        return address?.url
    }

    /// A build to offer, and whether it's a test build.
    struct Offer: Equatable {
        let build: Int
        let isTest: Bool
    }

    /// What a copy on build `current` is offered: the newest build released to everyone,
    /// or, with test builds wanted, the newest build there is. Nothing if it has that already.
    static func offer(current: Int, released: Int?, test: Int?, wantsTest: Bool) -> Offer? {
        let everyone = released ?? 0
        let newest = wantsTest ? max(everyone, test ?? 0) : everyone
        guard newest > current, newest > 0 else { return nil }
        return Offer(build: newest, isTest: newest > everyone)
    }

    /// How Settings puts it: "Build 44 is ready to install" or, for a test build, that
    /// it hasn't been released to everyone yet.
    static func readyText(build: Int, isTest: Bool) -> String {
        isTest ? "Build \(build) is ready to install: a test build, not released to everyone yet"
               : "Build \(build) is ready to install"
    }

    /// Under "Get test builds", for whoever releases the builds: where things stand.
    static func releaseStanding(current: Int, released: Int?) -> String {
        guard let released = released else {
            return "Checking which build everyone has…"
        }
        if current > released {
            return "This Mac is on Build \(current), a test build. Everyone else is offered Build \(released)."
        }
        if current == released {
            return "Build \(current) is released: every copy is offered it."
        }
        return "Everyone is offered Build \(released)."
    }

    /// What to do on the page that "Release Build 44 to Everyone…" opens.
    static func releaseSteps(build: Int) -> String {
        "GitHub opens in your browser. Click Run workflow, type \(build), then click the green Run workflow button. Only the repository's owner can, signed in to GitHub. Every copy is offered the build within a couple of minutes."
    }

    /// Whether this Mac's build is one that could be released now: it's newer than the
    /// one everyone has.
    static func canRelease(current: Int, released: Int?) -> Bool {
        guard let released = released else { return false }
        return current > released && current >= firstWithTestBuilds
    }

    /// Why GitHub's API didn't say which build is newest, in words.
    static func problem(status: Int, error: Error?, remaining: String?, reset: String?) -> String {
        if let error = error {
            return "GitHub couldn't be reached (\(error.localizedDescription))."
        }
        if status == 403 || status == 429 {
            guard remaining == "0" else { return "GitHub turned the check away (HTTP \(status))." }
            var text = "GitHub allows 60 update checks an hour from your network, shared by every app on it, and they're used up"
            if let seconds = reset.flatMap(TimeInterval.init) {
                let time = DateFormatter()
                time.dateStyle = .none
                time.timeStyle = .short
                text += " until \(time.string(from: Date(timeIntervalSince1970: seconds)))"
            }
            return text + "."
        }
        if status >= 500 {
            return "GitHub had a problem (HTTP \(status)). Try again in a minute."
        }
        return status == 0 ? "GitHub didn't answer." : "GitHub answered HTTP \(status)."
    }
}

/// Looks for test builds. They aren't GitHub's "latest release", so github.com is asked
/// whether each build after the newest one known has a page yet, stopping after a few in a
/// row that don't. (A build that failed to publish leaves a gap in the numbers.)
struct BuildSearch: Equatable {
    /// The newest build known to exist.
    private(set) var newest: Int
    /// Builds in a row, after the newest, that turned out not to exist.
    private(set) var misses = 0
    /// How many pages have been asked for.
    private(set) var looked = 0
    /// GitHub didn't answer properly: the search stops, keeping what it found.
    private(set) var stopped = false
    /// Whether anything newer than where it started was found.
    private(set) var foundNewer = false

    /// How many builds in a row may be missing before the search gives up.
    static let gap = 3
    /// The most pages asked for in one check.
    static let most = 24

    init(after base: Int) {
        newest = max(0, base)
    }

    /// The build to ask about next; nil when the search is over.
    var next: Int? {
        guard !stopped, misses < BuildSearch.gap, looked < BuildSearch.most else { return nil }
        return newest + misses + 1
    }

    /// github.com answered for a build's page: 200 means it's there, 404 that it isn't.
    /// Anything else (no connection, a server error) ends the search for now.
    mutating func saw(_ build: Int, status: Int) {
        guard build == next else { return }
        looked += 1
        switch status {
        case 200:
            newest = build
            misses = 0
            foundNewer = true
        case 404:
            misses += 1
        default:
            stopped = true
        }
    }

    /// For Copy Debug Info: "looked at 3 builds, none newer than build 44".
    var summary: String {
        let pages = looked == 1 ? "1 build" : "\(looked) builds"
        if stopped {
            return "looked at \(pages), then github.com stopped answering"
        }
        return foundNewer ? "looked at \(pages), newest is build \(newest)" : "looked at \(pages), none newer than build \(newest)"
    }
}
