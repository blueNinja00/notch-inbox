import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: On the primary menu

/// The row under the primary menu's tiles: what's playing, the focus timer, the clipboard
/// and the shelf. Each can be switched off in Settings → Extras.
struct ExtrasStrip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            if settings.showsNowPlaying {
                NowPlayingChip(model: model, watcher: NowPlayingWatcher.shared)
            }
            if settings.showsFocus {
                FocusChip(model: model, timer: FocusTimer.shared)
                    .frame(width: 212)
            }
            if settings.keepsClipboard {
                ClipboardChip(model: model, watcher: ClipboardWatcher.shared)
                    .frame(width: 170)
            }
            if settings.showsShelf, let shelf = model.shelfStore {
                ShelfChip(model: model, store: shelf)
            }
        }
    }
}

/// The look every chip in the row shares.
struct ChipBackground: ViewModifier {
    var lit = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(lit ? 0.3 : 0), lineWidth: 1)
            )
    }
}

/// A chip's round icon.
struct ChipIcon: View {
    let symbol: String
    var tint: Color = Theme.text

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Theme.raised))
    }
}

// MARK: Now playing

/// What's playing in Spotify or Music, with previous, play or pause, and next.
struct NowPlayingChip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var watcher: NowPlayingWatcher

    var body: some View {
        HStack(spacing: 8) {
            ChipIcon(symbol: "music.note", tint: watcher.track?.isPlaying == true ? Theme.text : Theme.tertiary)
            Text(NowPlayingChip.line(track: watcher.track, player: watcher.player, problem: watcher.problem))
                .font(.system(size: 12, weight: watcher.track == nil ? .regular : .semibold))
                .foregroundStyle(watcher.track == nil ? Theme.tertiary : Theme.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if watcher.player != nil {
                MusicButtons(watcher: watcher, size: 26)
            }
        }
        .modifier(ChipBackground())
        .contentShape(Rectangle())
        .onTapGesture { model.openExtras() }
        .help(watcher.problem ?? (watcher.track.map { "\($0.line) · \($0.player.name)" } ?? "What's playing in Spotify or Music shows here"))
    }

    /// The chip's one line: the song, or what to do to see one.
    static func line(track: NowPlayingTrack?, player: MusicPlayer?, problem: String?) -> String {
        if let track = track { return track.line }
        if problem != nil, let player = player { return "Allow Notch Inbox to control \(player.name)" }
        if let player = player { return "\(player.name) is open" }
        return "Nothing playing"
    }
}

/// Previous, play or pause, next.
struct MusicButtons: View {
    @ObservedObject var watcher: NowPlayingWatcher
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "backward.fill", label: "Previous", size: size, tint: Theme.text2, action: { watcher.send(.previous) })
            IconButton(symbol: watcher.track?.isPlaying == true ? "pause.fill" : "play.fill",
                       label: watcher.track?.isPlaying == true ? "Pause" : "Play", size: size, tint: Theme.text,
                       action: { watcher.send(.playPause) })
            IconButton(symbol: "forward.fill", label: "Next", size: size, tint: Theme.text2, action: { watcher.send(.next) })
        }
    }
}

// MARK: Focus

/// The focus timer: start a round, watch it count down, take a break.
struct FocusChip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var timer: FocusTimer

    var body: some View {
        HStack(spacing: 8) {
            if let session = timer.session {
                FocusRing(session: session)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: -1) {
                    FocusClock(session: session, size: 13)
                    Text(FocusChip.caption(session))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                FocusButtons(model: model, timer: timer, session: session, size: 26)
            } else {
                ChipIcon(symbol: "timer")
                VStack(alignment: .leading, spacing: -1) {
                    Text("Focus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("\(timer.focusMinutes) minutes")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                IconButton(symbol: "play.fill", label: "Start \(timer.focusMinutes) minutes of focus", size: 26, tint: Theme.text,
                           action: { timer.start() })
            }
        }
        .modifier(ChipBackground(lit: timer.session?.finished == true))
        .contentShape(Rectangle())
        .onTapGesture { model.openExtras() }
    }

    /// What's under the clock: what you're doing, or what happens next.
    static func caption(_ session: FocusSession) -> String {
        if session.finished { return session.phase == .focus ? "Time's up. Take a break?" : "Break's over" }
        if session.isPaused { return "Paused" }
        if session.phase == .rest { return "Break" }
        return session.title.isEmpty ? "Focus" : session.title
    }
}

/// The time left, ticking.
struct FocusClock: View {
    let session: FocusSession
    var size: CGFloat = 13

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            Text(session.finished ? "Done" : FocusSession.clock(session.remaining(now: context.date)))
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundStyle(session.finished ? Theme.warning : Theme.text)
        }
    }
}

/// A ring that fills as the time goes.
struct FocusRing: View {
    let session: FocusSession

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 5)) { context in
            ZStack {
                Circle()
                    .stroke(Theme.raised, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(session.progress(now: context.date)))
                    .stroke(session.phase == .focus ? Theme.accent : Theme.good, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(1.5)
        }
    }
}

/// What you can do with the timer right now.
struct FocusButtons: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var timer: FocusTimer
    let session: FocusSession
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            if session.finished {
                if session.phase == .focus {
                    if let task = session.taskID, let store = model.plannerStore, store.planner.task(task)?.done == false {
                        IconButton(symbol: "checkmark.circle", label: "Tick off \(session.title)", size: size, tint: Theme.text2,
                                   action: { store.change { $0.setDone(task, true) } })
                    } else if let step = session.taskID, let store = model.assignmentsStore,
                              store.assignments.owner(of: step)?.steps.contains(where: { $0.id == step && !$0.done }) == true {
                        // The round was for a step of an assignment.
                        IconButton(symbol: "checkmark.circle", label: "Tick off \(session.title)", size: size, tint: Theme.text2,
                                   action: { store.change { $0.setStep(step, done: true) } })
                    }
                    IconButton(symbol: "cup.and.saucer.fill", label: "Start a \(timer.breakMinutes)-minute break", size: size, tint: Theme.text,
                               action: { timer.startBreak() })
                } else {
                    IconButton(symbol: "play.fill", label: "Start another round", size: size, tint: Theme.text, action: { timer.start() })
                }
                IconButton(symbol: "xmark", label: "Clear the timer", size: size, tint: Theme.tertiary, action: { timer.stop() })
            } else {
                if session.isPaused {
                    IconButton(symbol: "play.fill", label: "Carry on", size: size, tint: Theme.text, action: { timer.resume() })
                } else {
                    IconButton(symbol: "pause.fill", label: "Pause", size: size, tint: Theme.text2, action: { timer.pause() })
                }
                IconButton(symbol: "stop.fill", label: "Stop the timer", size: size, tint: Theme.tertiary, action: { timer.stop() })
            }
        }
    }
}

/// The timer's minutes beside the closed notch.
struct FocusEar: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        if let session = timer.session {
            TimelineView(.periodic(from: Date(), by: 10)) { context in
                Text(session.finished ? "Done" : FocusSession.short(session.remaining(now: context.date)))
                    .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(session.finished ? Theme.warning : (session.phase == .focus ? Theme.text2 : Theme.good))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: Clipboard

/// How many things you've copied lately; click for the list.
struct ClipboardChip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var watcher: ClipboardWatcher

    var body: some View {
        let clips = watcher.list.clips

        HStack(spacing: 8) {
            ChipIcon(symbol: "doc.on.clipboard")
            VStack(alignment: .leading, spacing: -1) {
                Text("Clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                Text(clips.isEmpty ? "Nothing copied yet" : "\(clips.count) to copy again")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .modifier(ChipBackground())
        .contentShape(Rectangle())
        .onTapGesture { model.openExtras() }
        .help("The last things you copied, kept in memory only. Click to copy one again.")
    }
}

// MARK: Shelf

/// Loads the files from a drop onto the shelf.
enum ShelfDrop {
    static let types: [UTType] = [.fileURL]

    @discardableResult
    static func take(_ providers: [NSItemProvider], into store: ShelfStore) -> Bool {
        var any = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            any = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    store.add([url])
                }
            }
        }
        return any
    }
}

/// The shelf on the primary menu: drop files here; drag them back out.
struct ShelfChip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: ShelfStore
    @State private var targeted = false

    init(model: NotchModel, store: ShelfStore) {
        self.model = model
        self.store = store
    }

    var body: some View {
        let items = store.items

        HStack(spacing: 8) {
            ChipIcon(symbol: "tray.and.arrow.down", tint: targeted ? Theme.text : Theme.secondary)
            if items.isEmpty {
                Text(targeted ? "Drop to park it here" : "Drop files here")
                    .font(.system(size: 12))
                    .foregroundStyle(targeted ? Theme.text2 : Theme.tertiary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    ForEach(items.prefix(5)) { item in
                        ShelfIcon(item: item, size: 24)
                    }
                }
                if items.count > 5 {
                    Text("+\(items.count - 5)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .modifier(ChipBackground(lit: targeted))
        .contentShape(Rectangle())
        .onTapGesture { model.openExtras() }
        .onDrop(of: ShelfDrop.types, isTargeted: $targeted) { providers in
            ShelfDrop.take(providers, into: store)
        }
        .help("Drop files here to park them, then drag them out where they're going")
    }
}

/// A file's icon, which you can drag out to wherever the file is going.
struct ShelfIcon: View {
    let item: ShelfItem
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .onDrag { NSItemProvider(object: item.url as NSURL) }
            .help(item.name)
    }
}

// MARK: The Extras panel

/// The extras with room to breathe: the shelf, the clipboard, and what's playing, the focus
/// timer and your phone down the side.
struct ExtrasView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    let expanded: Bool

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "tray.full", title: "Extras") {
                    EmptyView()
                }
            } trailing: {
                HStack(spacing: 2) {
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make it smaller" : "Expand",
                               action: { expanded ? model.back() : model.expandExtras() })
                    SettingsButton(model: model, section: .extras)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                if settings.showsShelf, let shelf = model.shelfStore {
                    ShelfPanel(store: shelf)
                }
                if settings.keepsClipboard {
                    ClipboardPanel(watcher: ClipboardWatcher.shared)
                        .frame(width: settings.showsShelf ? (expanded ? 320 : 280) : nil)
                }
                ExtrasSide(model: model, settings: settings, phone: PhoneCableWatcher.shared)
                    .frame(width: expanded ? 270 : 244)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// A panel's heading, with room for buttons on the right.
struct PanelHeading<Buttons: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            buttons()
        }
        .foregroundStyle(Theme.text)
        .frame(height: 24)
    }
}

/// The shelf: every file parked on it. Drop more anywhere on it; drag any back out.
struct ShelfPanel: View {
    @ObservedObject var store: ShelfStore
    @State private var targeted = false

    init(store: ShelfStore) {
        self.store = store
    }

    var body: some View {
        let items = store.items

        VStack(alignment: .leading, spacing: 8) {
            PanelHeading(symbol: "tray.and.arrow.down", title: items.isEmpty ? "Shelf" : "Shelf · \(items.count)") {
                if !items.isEmpty {
                    SmallPill(title: "AirDrop", symbol: "dot.radiowaves.left.and.right", action: { ShelfPanel.airDrop(items) })
                        .help("Send everything on the shelf by AirDrop")
                    SmallPill(title: "Clear", symbol: "xmark", action: { store.clear() })
                        .help("Take everything off the shelf (the files themselves stay where they are)")
                }
            }
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(targeted ? Theme.text2 : Theme.tertiary)
                    Text(targeted ? "Drop to park it here" : "Drop files here to park them")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Drag a file to the notch and it opens. Later, drag files from here to wherever they're going: an email, a folder, a chat. They aren't copied or moved.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(items) { item in
                            ShelfRow(item: item, remove: { store.remove(item.id) })
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(targeted ? 0.3 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .onDrop(of: ShelfDrop.types, isTargeted: $targeted) { providers in
            ShelfDrop.take(providers, into: store)
        }
        .onAppear { store.prune() }
    }

    static func airDrop(_ items: [ShelfItem]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let urls = items.map { $0.url as NSURL }
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        }
    }
}

/// One file on the shelf: drag it out, double-click to open it.
struct ShelfRow: View {
    let item: ShelfItem
    let remove: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .truncationMode(.middle)
                Text(ShelfRow.folder(of: item.url))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .truncationMode(.head)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                IconButton(symbol: "magnifyingglass", label: "Show in Finder", size: 24, tint: Theme.secondary,
                           action: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) })
                IconButton(symbol: "xmark", label: "Take off the shelf", size: 24, tint: Theme.tertiary, action: remove)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.hover.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy Its Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Take Off the Shelf", action: remove)
        }
        .help("Drag it to where it's going · double-click to open it")
    }

    /// "~/Desktop", "~/Documents/School".
    static func folder(of url: URL) -> String {
        let path = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }
}

/// The last things you copied. Click one to copy it again.
struct ClipboardPanel: View {
    @ObservedObject var watcher: ClipboardWatcher
    @State private var copied: UUID?

    init(watcher: ClipboardWatcher) {
        self.watcher = watcher
    }

    var body: some View {
        let clips = watcher.list.clips

        VStack(alignment: .leading, spacing: 8) {
            PanelHeading(symbol: "doc.on.clipboard", title: clips.isEmpty ? "Clipboard" : "Clipboard · \(clips.count)") {
                if !clips.isEmpty {
                    SmallPill(title: "Clear", symbol: "xmark", action: { watcher.clear() })
                        .help("Forget everything copied")
                }
            }
            if clips.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing copied yet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("The last 30 things you copy show here; click one to copy it again. They're kept in memory only, never saved or sent anywhere, and passwords from password managers are skipped.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(clips) { clip in
                            ClipRow(clip: clip, copied: copied == clip.id, copy: { copy(clip) }, remove: { watcher.remove(clip.id) })
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private func copy(_ clip: Clip) {
        watcher.copy(clip)
        // The list reorders with the copied clip first; the tick follows it there.
        let top = watcher.list.clips.first?.id
        copied = top
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copied == top { copied = nil }
        }
    }
}

/// One thing you copied.
struct ClipRow: View {
    let clip: Clip
    let copied: Bool
    let copy: () -> Void
    let remove: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(clip.preview)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text2)
                    Text(ClipRow.detail(clip, copied: copied))
                        .font(.system(size: 10.5))
                        .foregroundStyle(copied ? Theme.good : Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(copied ? Theme.good : Theme.tertiary)
                    .opacity(hovering || copied ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.hover.opacity(0.6) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy Again", action: copy)
            Button("Forget This One", action: remove)
        }
        .help("Click to copy it again")
    }

    /// "Copied", or "3 lines · 2:41 pm".
    static func detail(_ clip: Clip, copied: Bool) -> String {
        if copied { return "Copied: paste it anywhere" }
        let lines = clip.lineCount
        let size = lines > 1 ? "\(lines) lines" : "\(clip.text.count) character\(clip.text.count == 1 ? "" : "s")"
        return "\(size) · \(MailTime.label(for: clip.at))"
    }
}

/// Down the side of the Extras panel: what's playing, the focus timer, and your phone.
struct ExtrasSide: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var phone: PhoneCableWatcher

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 10) {
                if settings.showsNowPlaying {
                    NowPlayingCard(watcher: NowPlayingWatcher.shared)
                }
                if settings.showsFocus {
                    FocusCard(model: model, timer: FocusTimer.shared)
                }
                if let details = phone.details {
                    PhoneCard(details: details, canAskBattery: PhoneCableWatcher.batteryTool != nil)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// What's playing, with bigger buttons.
struct NowPlayingCard: View {
    @ObservedObject var watcher: NowPlayingWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeading(symbol: "music.note", title: watcher.player?.name ?? "Now playing") {
                EmptyView()
            }
            if let track = watcher.track {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title.isEmpty ? "Unknown" : track.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
            } else {
                Text(watcher.player == nil ? "Open Spotify or Music and what's playing shows here." : "Press play, or change the song, and it shows here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = watcher.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if watcher.player != nil {
                MusicButtons(watcher: watcher, size: 30)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// The focus timer, with its lengths to pick from.
struct FocusCard: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var timer: FocusTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeading(symbol: "timer", title: timer.rounds == 0 ? "Focus" : "Focus · \(timer.rounds) done today") {
                EmptyView()
            }
            if let session = timer.session {
                HStack(spacing: 10) {
                    FocusRing(session: session)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        FocusClock(session: session, size: 20)
                        Text(FocusChip.caption(session))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    FocusButtons(model: model, timer: timer, session: session, size: 28)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(FocusTimer.focusChoices, id: \.self) { minutes in
                        FocusLength(minutes: minutes, chosen: timer.focusMinutes == minutes, start: {
                            timer.focusMinutes = minutes
                            timer.start()
                        })
                    }
                }
                Text("Pick a length to start. A chime and the notch tell you when it's up.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// "25", to start that many minutes of focus.
struct FocusLength: View {
    let minutes: Int
    let chosen: Bool
    let start: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: start) {
            VStack(spacing: -1) {
                Text("\(minutes)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                Text("min")
                    .font(.system(size: 9.5, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(chosen ? Theme.onAccent : Theme.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chosen ? Theme.accent.opacity(hovering ? 1 : 0.92) : (hovering ? Theme.hover : Theme.raised)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Start \(minutes) minutes of focus")
    }
}

/// The phone on the cable: what it is, how fast the cable is, and its battery if that's known.
struct PhoneCard: View {
    let details: PhoneDetails
    let canAskBattery: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeading(symbol: "iphone", title: details.name) {
                PhoneDot(size: 6)
            }
            Text([details.maker, details.speed ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            if let battery = details.battery {
                HStack(spacing: 6) {
                    Image(systemName: battery.charging ? "battery.100.bolt" : "battery.75")
                        .font(.system(size: 12))
                    Text(battery.text)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(battery.percent <= 20 && !battery.charging ? Theme.danger : Theme.text2)
            } else if details.name.lowercased().contains("iphone") {
                Text(canAskBattery
                     ? "Battery: unlock the iPhone and tap Trust, and its level shows here."
                     : "macOS doesn't tell apps an iPhone's battery level. To see it here, install libimobiledevice (in Terminal: brew install libimobiledevice).")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}
