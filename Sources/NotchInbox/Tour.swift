import Foundation

/// One page of the tour: a tool, what it's for in a sentence, a few things to know, and a
/// button to go and try it.
struct TourPage: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case welcome
        case mail
        case planner
        case assignments
        case timetable
        case notes
        case assistant
        case agents
        case extras
        case looks
        case privacy
        case done
    }

    /// One thing to know, with a small symbol beside it.
    struct Point: Equatable, Identifiable {
        let symbol: String
        let text: String

        var id: String { text }
    }

    /// Where a page's button takes you.
    enum Target: Equatable {
        case mail
        case planner
        case timetable
        case notes
        case assistant
        case extras
        case bookmarks
        case assignments
        case agents
        case settings(SettingsSection)
    }

    struct Action: Equatable {
        let title: String
        let target: Target
    }

    let kind: Kind
    let symbol: String
    let title: String
    let summary: String
    let points: [Point]
    var action: Action?

    var id: String { kind.rawValue }
}

/// The tour that opens the first time the app runs: what the notch is, then each tool in
/// turn. It's written here, apart from how it's drawn, and worded to fit how the app is set
/// up (sample mail or your own, Claude or Qwen, the notch or the mail tab).
enum Tour {
    /// Raise this when the tour changes enough that people who've seen it should be offered
    /// it again.
    static let version = 1
    /// How many pages there are, however the app is set up.
    static let pageCount = TourPage.Kind.allCases.count

    static let seenKey = "tourSeenVersion"
    static let offeredKey = "tourOfferedVersion"

    /// How the app is set up, as far as the tour's wording cares.
    struct Setup: Equatable {
        /// Real Gmail is showing, not sample mail.
        var gmailLinked = false
        /// "Claude" or "Qwen".
        var assistantName = "Claude"
        var assistantIsClaude = true
        var assistantReady = false
        /// Shown as the small mail tab, not at the notch.
        var mailTab = false
        /// Any of the extras is switched on.
        var extrasOn = true
        /// How many inboxes are in the notch, and how many more are linked and could be added.
        var inboxes = 1
        var inboxesToAdd = 2
    }

    // MARK: Whether to show it

    /// Not finished or skipped yet: the primary menu offers it.
    static func isPending(in defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: seenKey) < version
    }

    /// Never opened by itself yet: it opens once when the app starts, whether that's the
    /// first time ever or the first time after an update that brought the tour.
    static func opensAtLaunch(in defaults: UserDefaults = .standard) -> Bool {
        isPending(in: defaults) && defaults.integer(forKey: offeredKey) < version
    }

    /// It opened by itself: it won't again (the primary menu still offers it until it's finished).
    static func markOffered(in defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: offeredKey)
    }

    /// Finished, or skipped.
    static func markSeen(in defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: seenKey)
        defaults.set(version, forKey: offeredKey)
    }

    // MARK: What it says

    /// Mail's point about choosing which inboxes show, for what's in the notch now.
    static func choosingInboxes(_ setup: Setup) -> String {
        if setup.inboxes > 1 {
            return "You choose which inboxes show. Point at an inbox's name for a minus that takes it out; \"Add an inbox\", in Mail, puts it back. Right-click a name to move it."
        }
        if setup.inboxesToAdd > 0 {
            return "It starts with one inbox. \"Add an inbox\", in Mail, puts another beside it. Point at an inbox's name for a minus that takes it out; right-click to move it."
        }
        return "It starts with one inbox. Sign in to another Gmail account in your browser and \"Add an inbox\" appears in Mail, to put it beside this one."
    }

    static func pages(for setup: Setup = Setup()) -> [TourPage] {
        TourPage.Kind.allCases.map { page($0, for: setup) }
    }

    static func page(_ kind: TourPage.Kind, for setup: Setup) -> TourPage {
        let assistant = setup.assistantName
        switch kind {
        case .welcome:
            return TourPage(
                kind: kind, symbol: "hand.wave", title: "Welcome to Notch Inbox",
                summary: "Your mail, homework, timetable and a few Mac helpers, tucked into the top of the screen. This tour takes about a minute.",
                points: [
                    .init(symbol: "cursorarrow.rays",
                          text: setup.mailTab
                              ? "Click the mail tab at the top of the screen and the primary menu opens, with a tile for each tool."
                              : "Move the pointer onto the notch and the primary menu drops down, with a tile for each tool."),
                    .init(symbol: "hand.tap", text: "Click a tile to open its tool. Click anywhere else on the screen and the notch closes."),
                    .init(symbol: "escape", text: "Esc goes back a step. The grid button at the top left of every tool goes back to the primary menu."),
                    .init(symbol: "arrow.up.left.and.arrow.down.right", text: "Drag the bottom edge or corner of any panel to make it bigger or smaller."),
                ])
        case .mail:
            return TourPage(
                kind: kind, symbol: "envelope.fill", title: "Mail",
                summary: setup.gmailLinked
                    ? "Your Gmail inboxes side by side, up to three. Each one's unread count sits beside the notch."
                    : "Your Gmail inboxes side by side, up to three, each with its unread count beside the notch. You're looking at sample mail until you link Gmail.",
                points: [
                    .init(symbol: "envelope.open", text: "Click an email to read all of it here. With one open, O opens it in Gmail, where you reply."),
                    .init(symbol: "plus.circle", text: choosingInboxes(setup)),
                    .init(symbol: "checkmark.circle", text: "Reading an email here marks it read in the notch only; Gmail isn't changed. The tick on an inbox marks all of it read."),
                    .init(symbol: "magnifyingglass", text: "Press / to search senders and subjects. 1, 2 and 3 open each inbox."),
                ],
                action: setup.gmailLinked ? .init(title: "Open Mail", target: .mail) : .init(title: "Link Gmail", target: .settings(.gmail)))
        case .planner:
            return TourPage(
                kind: kind, symbol: "checklist", title: "Planner",
                summary: "Homework, exam countdowns, and a plan for when to do it all.",
                points: [
                    .init(symbol: "plus", text: "Type homework in one line, like \"Maths worksheet fri 4pm 45m\", and press Return. Tick it off when it's done."),
                    .init(symbol: "graduationcap", text: "Add an exam and it counts down in the planner and beside the date on the primary menu."),
                    .init(symbol: "clock", text: "The plan fits homework and revision into the free time on your timetable, soonest due first."),
                    .init(symbol: "studentdesk", text: "Google Classroom emails add their assignments by themselves, with their due dates. Your school account's inbox has to be in the notch."),
                ],
                action: .init(title: "Open the Planner", target: .planner))
        case .assignments:
            return TourPage(
                kind: kind, symbol: "list.bullet.clipboard", title: "Assignments and Marks",
                summary: "Bigger pieces of work, broken into steps, and the marks that come back.",
                points: [
                    .init(symbol: "plus", text: "The + adds an assignment. Or drop its task sheet on Assignments (a PDF, a Word file, a photo) and it's read and filled in for you."),
                    .init(symbol: "sparkles", text: setup.assistantReady
                              ? "Break into Steps has \(assistant) plan it from the task sheet. Research This sets three agents on it: sources, a plan to write from, then a check."
                              : "Break into Steps puts in the usual steps until \(assistant) is set up. Then Research This can set three agents finding sources and planning it."),
                    .init(symbol: "clock", text: "Tick the steps off as you go. The planner fits the ones still to do into your free time before it's due."),
                    .init(symbol: "chart.bar", text: "Marks keeps every result, your average in each subject, and what you need on the rest to reach the mark you're after."),
                ],
                action: .init(title: "Open Assignments", target: .assignments))
        case .timetable:
            return TourPage(
                kind: kind, symbol: "calendar", title: "Timetable",
                summary: "Your school week. The primary menu shows the class you're in now and the one after.",
                points: [
                    .init(symbol: "square.and.pencil", text: "Click any slot to put a lesson or activity in it: subject, room and teacher."),
                    .init(symbol: "calendar.badge.clock", text: "Week A and Week B, weekends, and hours before and after school are in Settings → Timetable."),
                    .init(symbol: "book", text: "Study the planner has planned shows faintly in this week's empty slots."),
                    .init(symbol: "sparkles", text: "Or just ask the assistant: \"put Soccer on Tuesdays at 5\"."),
                ],
                action: .init(title: "Open the Timetable", target: .timetable))
        case .notes:
            return TourPage(
                kind: kind, symbol: "note.text", title: "Notes and Bookmarks",
                summary: "Quick notes, and the pages you open every day, one hover away.",
                points: [
                    .init(symbol: "plus", text: "Click the Notes tile to write one. Its first line is its title."),
                    .init(symbol: "internaldrive", text: "Notes are saved on this Mac as you type."),
                    .init(symbol: "sparkles", text: "The assistant can read your latest notes, but only if you let it in Settings → Assistant."),
                    .init(symbol: "bookmark", text: "Bookmarks keeps your links: paste one in, or drag it from your browser. Click a bookmark on the tile and the page opens."),
                ],
                action: .init(title: "Open Notes", target: .notes))
        case .assistant:
            return TourPage(
                kind: kind, symbol: "sparkles", title: "Assistant",
                summary: "Your chief of staff. Ask \(assistant) anything, and have it keep your planner, timetable, assignments and bookmarks in order.",
                points: [
                    .init(symbol: "text.bubble", text: "Try \"what's due this week?\", \"add a Maths test on Friday at 9\" or \"I got 17 out of 20 on the Chemistry prac\"."),
                    .init(symbol: "keyboard", text: "On your Claude plan it can look things up on the web. The keyboard button beside an answer types it into the document you were in."),
                    .init(symbol: "cpu", text: "It runs on Claude, with your Claude plan or an API key, or on Qwen, which works entirely on this Mac."),
                    .init(symbol: "hand.raised", text: setup.assistantIsClaude
                              ? "Claude only sees what you allow in Settings → Assistant. Sharing your emails and notes with it is off to start with."
                              : "Qwen only sees what you allow in Settings → Assistant, and nothing it reads leaves this Mac."),
                ],
                action: .init(title: setup.assistantReady ? "Open the Assistant" : "Set Up the Assistant", target: .assistant))
        case .agents:
            return TourPage(
                kind: kind, symbol: "building.2", title: "Agents",
                summary: "Bigger jobs, handed to agents that work on them by themselves while you get on with something else.",
                points: [
                    .init(symbol: "arrow.up.circle", text: "Type a job in the agent room, like \"find five reliable sources on the Cold War and summarise each\", and an agent starts on it."),
                    .init(symbol: "building.2", text: "Each agent gets a floor. Watch what it's searching and reading, then read its report. A few work at once; the rest wait their turn."),
                    .init(symbol: "link", text: "Switch on Chain and three agents do the job in turn: one researches, one writes, one checks the links. Or ask the assistant, and it hands the big jobs out."),
                    .init(symbol: "hand.raised", text: "On your Claude plan, an agent can use the web and save files in a folder of its own. It can't run commands, and it can't see your mail, notes or other files."),
                ],
                action: .init(title: setup.assistantReady ? "Open the Agent Room" : "Set Up the Assistant", target: setup.assistantReady ? .agents : .assistant))
        case .extras:
            return TourPage(
                kind: kind, symbol: "tray.full", title: "Extras",
                summary: setup.extrasOn
                    ? "A row of Mac helpers under the tiles. Click any of them for more room."
                    : "A row of Mac helpers under the tiles. They're all switched off at the moment; Settings → Extras turns them on.",
                points: [
                    .init(symbol: "music.note", text: "Now playing: the song in Spotify or Music, with previous, play or pause, and next."),
                    .init(symbol: "timer", text: "Focus timer: a round of focus, then a break. The minutes left show beside the closed notch."),
                    .init(symbol: "doc.on.clipboard", text: "Clipboard: the last 30 things you copied, kept in memory only. Shelf: drag files to the notch to park them, then drag them out again."),
                    .init(symbol: "speaker.wave.2", text: "Volume and brightness: change either and the closed notch shows it for a moment. The Extras panel has a slider for each."),
                ],
                action: setup.extrasOn ? .init(title: "Open Extras", target: .extras) : .init(title: "Open Extras Settings", target: .settings(.extras)))
        case .looks:
            return TourPage(
                kind: kind, symbol: "paintpalette", title: "Make it yours",
                summary: "Settings is the gear at the top right of every panel.",
                points: [
                    .init(symbol: "paintpalette", text: "Eight themes to choose from: click one on the right to try it now. Or make your own from any colour in Settings → General."),
                    .init(symbol: "menubar.rectangle", text: setup.mailTab
                              ? "You're using the mail tab. Settings → General puts Notch Inbox back at the notch."
                              : "Rather not use the notch? Settings → General swaps it for a small mail tab you can slide along the top."),
                    .init(symbol: "square.grid.2x2", text: "The primary menu is yours to arrange: right-click a tile to move it or hide it, or set the order in Settings → General."),
                    .init(symbol: "arrow.down.circle", text: "New builds install from Settings → Updates. An Update button appears in the notch when one is ready."),
                ],
                action: .init(title: "Open Settings", target: .settings(.general)))
        case .privacy:
            return TourPage(
                kind: kind, symbol: "lock.shield", title: "What stays on your Mac",
                summary: "Nearly everything. This is what does go online, and when.",
                points: [
                    .init(symbol: "internaldrive", text: "Your mail, notes, timetable, planner, assignments and bookmarks are kept on this Mac. Mail comes straight from your browser to this app."),
                    .init(symbol: "sparkles", text: "Questions you ask Claude, and jobs you give its agents, go to Anthropic with only what you've allowed it to see. So does what they search the web for. Qwen stays on this Mac."),
                    .init(symbol: "photo", text: "Opening an email loads its pictures from the web, the way Gmail does."),
                    .init(symbol: "arrow.down.circle", text: "Checking for updates asks GitHub for the newest build."),
                ])
        case .done:
            var points: [TourPage.Point] = []
            if !setup.gmailLinked {
                points.append(.init(symbol: "link", text: "Link Gmail to see your own mail: Settings → Gmail link walks you through it."))
            }
            points.append(.init(symbol: "calendar", text: "Fill in your timetable, so the planner knows when you're free."))
            points.append(.init(symbol: "checklist", text: "Add your first homework or exam."))
            if !setup.assistantReady {
                points.append(.init(symbol: "sparkles", text: "Set up \(assistant) when you want to ask it things."))
            }
            return TourPage(
                kind: kind, symbol: "checkmark.seal.fill", title: "You're set",
                summary: "That's everything. To see this tour again, open Settings → General and click Show the Tour.",
                points: points,
                action: setup.gmailLinked ? nil : .init(title: "Link Gmail", target: .settings(.gmail)))
        }
    }
}
