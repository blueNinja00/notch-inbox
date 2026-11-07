// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "NotchInbox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NotchInbox",
            path: "Sources/NotchInbox"
        )
    ]
)
