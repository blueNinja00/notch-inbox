import Foundation

/// A music app the notch can show and control.
enum MusicPlayer: String, CaseIterable, Equatable {
    case spotify
    case music

    var name: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    /// The notice the app posts whenever what's playing changes. macOS delivers it to any
    /// app that listens; no permission is involved.
    var notice: String {
        switch self {
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        case .music: return "com.apple.Music.playerInfo"
        }
    }
}

/// What's playing.
struct NowPlayingTrack: Equatable {
    var player: MusicPlayer
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool

    /// "Song · Artist", or whichever there is.
    var line: String {
        [title, artist].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Play, pause and skip.
enum MusicCommand: Equatable {
    case playPause
    case next
    case previous
}

/// The parts of Now Playing that need no Mac: reading the players' notices, and the
/// AppleScript for each button.
enum NowPlaying {
    /// What a player's notice says is playing. Nil when it has stopped, or says nothing useful.
    static func track(from info: [AnyHashable: Any], player: MusicPlayer) -> NowPlayingTrack? {
        let state = ((info["Player State"] as? String) ?? "").lowercased()
        guard state == "playing" || state == "paused" else { return nil }
        let title = text(info["Name"])
        let artist = text(info["Artist"])
        guard !title.isEmpty || !artist.isEmpty else { return nil }
        return NowPlayingTrack(player: player, title: title, artist: artist, album: text(info["Album"]), isPlaying: state == "playing")
    }

    private static func text(_ value: Any?) -> String {
        ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The AppleScript for a button. It names the app by its ID, so it can't start some other app.
    static func script(_ command: MusicCommand, for player: MusicPlayer) -> String {
        let action: String
        switch command {
        case .playPause: action = "playpause"
        case .next: action = "next track"
        case .previous: action = "previous track"
        }
        return "tell application id \"\(player.bundleID)\" to \(action)"
    }

    /// Asks a player what's playing, as three lines: name, artist, state. Only used after
    /// you've pressed a button (which is when macOS asks whether the notch may control it).
    static func query(for player: MusicPlayer) -> String {
        """
        tell application id "\(player.bundleID)"
            if player state is stopped then return ""
            return (name of current track) & linefeed & (artist of current track) & linefeed & (player state as string)
        end tell
        """
    }

    /// Reads the answer to `query`.
    static func track(fromAnswer answer: String, player: MusicPlayer) -> NowPlayingTrack? {
        let lines = answer.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.count >= 3, !lines[0].isEmpty || !lines[1].isEmpty else { return nil }
        let state = lines[2].lowercased()
        guard state.contains("playing") || state.contains("paused") else { return nil }
        return NowPlayingTrack(player: player, title: lines[0], artist: lines[1], album: "", isPlaying: state.contains("playing"))
    }

    /// What to say when a button didn't work.
    static func problem(_ errorOutput: String, player: MusicPlayer) -> String {
        let lower = errorOutput.lowercased()
        if lower.contains("-1743") || lower.contains("not authorized") || lower.contains("not allowed") {
            return "macOS hasn't let Notch Inbox control \(player.name). Allow it in System Settings → Privacy & Security → Automation."
        }
        if lower.contains("-600") || lower.contains("isn't running") || lower.contains("not running") {
            return "\(player.name) isn't open."
        }
        return "\(player.name) didn't answer."
    }
}
