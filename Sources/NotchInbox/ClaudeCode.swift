import Foundation

/// Runs Claude Code (`claude`) on this Mac to answer, signed in with your Claude account.
/// Each question is one `claude -p` run with no tools, in a folder of its own, and nothing
/// is saved to your Claude Code history.
enum ClaudeCode {
    /// Where `claude` is, or nil if it isn't installed anywhere the app can see.
    static func find() -> String? {
        let files = FileManager.default
        let home = NSHomeDirectory()
        for path in ClaudeStream.claudeLocations(home: home) where files.isExecutableFile(atPath: path) {
            return path
        }
        // Installed with npm under nvm: the newest Node first.
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? files.contentsOfDirectory(atPath: nvm) {
            for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                let path = "\(nvm)/\(version)/bin/claude"
                if files.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return askLoginShell()
    }

    /// Asks your login shell where `claude` is, for installs somewhere unusual. Gives up
    /// after five seconds.
    private static func askLoginShell() -> String? {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("notch-inbox-which-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v claude"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        let path = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.hasPrefix("/") }
        guard let found = path, FileManager.default.isExecutableFile(atPath: found) else { return nil }
        return found
    }

    /// Claude Code runs here, so no project's settings or CLAUDE.md get mixed in.
    private static var workFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("Notch Inbox", isDirectory: true).appendingPathComponent("Assistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    struct Outcome {
        let exitStatus: Int32
        let errorOutput: String
        /// Whether any line of the answer came back.
        let answered: Bool
        /// What the run used, as Claude Code counted it at the end. Nil if it never said
        /// (it was stopped, or couldn't start).
        var usage: TokenUse? = nil
    }

    /// Runs `claude` once, handing each piece of the answer to `onPiece` as it arrives.
    /// Cancelling the task stops Claude Code.
    static func run(path: String, arguments: [String], prompt: String,
                    onPiece: @escaping (StreamPiece) async -> Void) async throws -> Outcome {
        var answered = false
        let ended = try await runLines(path: path, arguments: arguments, prompt: prompt, folder: nil) { line in
            guard let piece = ClaudeStream.codePiece(fromLine: line) else { return }
            answered = true
            await onPiece(piece)
        }
        return Outcome(exitStatus: ended.exitStatus, errorOutput: ended.errorOutput, answered: answered, usage: ended.usage)
    }

    /// Runs `claude` once, handing each line of what it prints to `onLine` as it arrives.
    /// `folder` is where it runs: an agent's own folder, or the assistant's (which has no
    /// project settings in it) when nil. Cancelling the task stops Claude Code.
    static func runLines(path: String, arguments: [String], prompt: String, folder: URL?,
                         onLine: @escaping (String) async -> Void) async throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = folder ?? workFolder

        // Apps don't get your Terminal's PATH; npm installs need Node on it.
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let folders = [URL(fileURLWithPath: path).deletingLastPathComponent().path,
                       "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (folders + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        // Your question goes in through standard input, not the command line, where other
        // programs on the Mac could see it.
        let question = Data(prompt.utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            try? input.fileHandleForWriting.write(contentsOf: question)
            try? input.fileHandleForWriting.close()
        }
        let errorText = Task.detached { () -> String in
            let data = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
            return String(decoding: data.prefix(4000), as: UTF8.self)
        }

        var any = false
        var usage: TokenUse?
        try await withTaskCancellationHandler {
            for try await line in output.fileHandleForReading.bytes.lines {
                any = true
                if let counted = TokenUse.fromResult(line: line) {
                    usage = counted
                }
                await onLine(line)
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
        process.waitUntilExit()
        return Outcome(exitStatus: process.terminationStatus, errorOutput: await errorText.value, answered: any, usage: usage)
    }
}
