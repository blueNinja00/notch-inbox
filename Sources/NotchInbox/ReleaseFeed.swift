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
}
