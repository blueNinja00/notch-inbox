import Foundation

/// Copies the "Notch Inbox Link" add-on that ships inside the app to
/// ~/Library/Application Support/Notch Inbox, where Chrome loads it from.
/// Refreshed on every launch, so app updates carry add-on updates with them.
enum BrowserExtensionInstaller {
    static var bundledFolder: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true)
    }

    static var installedFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Notch Inbox Link", isDirectory: true)
    }

    @discardableResult
    static func install() throws -> URL {
        guard let source = bundledFolder, FileManager.default.fileExists(atPath: source.path) else {
            throw LinkError("This copy of Notch Inbox doesn't include the browser add-on. Reinstall it with the command in the README.")
        }
        let target = installedFolder
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        // Replace file by file, so a browser that has the folder loaded never sees it vanish.
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file, to: destination)
        }
        return target
    }

    static func refreshIfInstalled() {
        if FileManager.default.fileExists(atPath: installedFolder.path) {
            _ = try? install()
        }
    }
}

struct LinkError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
