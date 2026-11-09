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
    static func release(build: Int, site: URL, repository: String, assetName: String) -> ReleaseInfo {
        let link = site.appendingPathComponent("\(repository)/releases/download/build-\(build)/\(assetName)")
        return ReleaseInfo(build: build, notes: "", downloadURL: link)
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
