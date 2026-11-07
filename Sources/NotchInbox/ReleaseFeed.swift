import Foundation

/// A build published on the repository's GitHub Releases page.
struct ReleaseInfo: Equatable {
    let build: Int
    let notes: String
    let downloadURL: URL
}

/// Reads GitHub's "latest release" response. Release tags look like "build-12",
/// and the number matches the app's CFBundleVersion.
enum ReleaseFeed {
    private struct Response: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
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
        return ReleaseInfo(build: build, notes: response.body ?? "", downloadURL: asset.browserDownloadUrl)
    }

    static func buildNumber(from tag: String) -> Int? {
        Int(tag.drop(while: { !$0.isNumber }))
    }
}
