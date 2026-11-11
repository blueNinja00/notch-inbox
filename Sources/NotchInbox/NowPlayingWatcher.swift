import AppKit
import Combine

/// What Spotify or Music is playing, and the buttons to control it.
///
/// What's playing comes from the notices those apps post whenever it changes, which macOS
/// passes to any app that listens: no permission, nothing asked of them. The buttons send
/// the app an AppleScript command, and the first time you press one macOS asks whether
/// Notch Inbox may control that app. Nothing here uses the network.
final class NowPlayingWatcher: ObservableObject {
    static let shared = NowPlayingWatcher()

    @Published private(set) var track: NowPlayingTrack?
    /// The app the buttons control: the one playing, else whichever music app is open.
    @Published private(set) var player: MusicPlayer?
    /// Why the last button press didn't work, if it didn't.
    @Published private(set) var problem: String?

    private var notices: [NSObjectProtocol] = []
    private var appNotices: [NSObjectProtocol] = []
    /// Commands go out one at a time, off the main thread (macOS may stop to ask permission).
    private let queue = DispatchQueue(label: "NotchInbox.NowPlaying", qos: .userInitiated)

    var isWatching: Bool { !notices.isEmpty }

    func start() {
        guard notices.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in MusicPlayer.allCases {
            let notice = center.addObserver(forName: Notification.Name(player.notice), object: nil, queue: .main) { [weak self] note in
                self?.heard(note.userInfo ?? [:], from: player)
            }
            notices.append(notice)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let notice = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshPlayer()
            }
            appNotices.append(notice)
        }
        refreshPlayer()
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        notices.forEach { center.removeObserver($0) }
        notices = []
        let workspace = NSWorkspace.shared.notificationCenter
        appNotices.forEach { workspace.removeObserver($0) }
        appNotices = []
        track = nil
        player = nil
        problem = nil
    }

    private func heard(_ info: [AnyHashable: Any], from player: MusicPlayer) {
        if let heard = NowPlaying.track(from: info, player: player) {
            // One app pausing doesn't take over from the other one playing.
            if heard.isPlaying || track == nil || track?.player == player || track?.isPlaying == false {
                track = heard
                problem = nil
            }
        } else if track?.player == player {
            track = nil
        }
        refreshPlayer()
    }

    static func isRunning(_ player: MusicPlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    /// Works out which app the buttons control, and forgets a track whose app has quit.
    private func refreshPlayer() {
        let running = MusicPlayer.allCases.filter { NowPlayingWatcher.isRunning($0) }
        if let current = track, !running.contains(current.player) {
            track = nil
        }
        let target = track?.player ?? running.first
        if player != target {
            player = target
        }
        if target == nil && problem != nil {
            problem = nil
        }
    }

    /// Play or pause, or skip. Does nothing if no music app is open (it never starts one).
    func send(_ command: MusicCommand) {
        refreshPlayer()
        guard let target = player else { return }
        let unknown = track == nil
        queue.async { [weak self] in
            let sent = NowPlayingWatcher.run(NowPlaying.script(command, for: target))
            var found: NowPlayingTrack?
            if sent.ok && unknown {
                // The app was already playing when the notch started: ask what it is.
                Thread.sleep(forTimeInterval: 0.3)
                let answer = NowPlayingWatcher.run(NowPlaying.query(for: target))
                if answer.ok {
                    found = NowPlaying.track(fromAnswer: answer.output, player: target)
                }
            }
            let failure = sent.ok ? nil : NowPlaying.problem(sent.error, player: target)
            DispatchQueue.main.async {
                guard let self = self, self.isWatching else { return }
                if let found = found, self.track == nil {
                    self.track = found
                }
                if self.problem != failure {
                    self.problem = failure
                }
                self.refreshPlayer()
            }
        }
    }

    /// Runs one AppleScript with macOS's own `osascript`.
    private static func run(_ script: String) -> (ok: Bool, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return (false, "", error.localizedDescription)
        }
        let said = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        let complained = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return (process.terminationStatus == 0,
                String(decoding: said.prefix(2000), as: UTF8.self),
                String(decoding: complained.prefix(2000), as: UTF8.self))
    }
}
