import Foundation
#if canImport(Combine)
import Combine
#endif

/// Where Settings opens to, and its sections down the left side.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case accounts
    case assistant
    case timetable
    case planner
    case extras
    case gmail
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .accounts: return "Mail accounts"
        case .assistant: return "Assistant"
        case .timetable: return "Timetable"
        case .planner: return "Planner"
        case .extras: return "Extras"
        case .gmail: return "Gmail link"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .accounts: return "tray.2"
        case .assistant: return "sparkles"
        case .timetable: return "calendar"
        case .planner: return "checklist"
        case .extras: return "tray.full"
        case .gmail: return "link"
        case .updates: return "arrow.down.circle"
        }
    }
}

/// What Settings shows about the app, kept up to date by the app delegate, and what its
/// buttons ask the app to do. One for every screen's notch.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// A linked Gmail account and what the notch shows of it.
    struct Account: Identifiable, Equatable {
        /// The address.
        let id: String
        var inbox: InboxChoice
        var hidden: Bool
        /// In the notch now: not hidden, and among the first three.
        var inNotch: Bool
        var unread: Int
        var colorHex: UInt32?
    }

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(build: Int, notes: String)
        case installing
        case failed(String)
        /// Running from somewhere other than an installed copy, e.g. while developing.
        case unavailable
    }

    /// How the Gmail link is doing.
    struct LinkStatus: Equatable {
        var lastSync: Date?
        var accounts = 0
        /// The add-on that last sent mail, e.g. "1.6.0"; nil before it's been heard from.
        var addOnRunning: String?
        /// The add-on in the folder Chrome loads it from.
        var addOnInstalled: String?
        var needsReload = false

        /// One line for the top of the Gmail link section.
        func summary(now: Date = Date()) -> String {
            guard let last = lastSync else { return "Not linked yet" }
            let when = MailTime.label(for: last, now: now)
            if now.timeIntervalSince(last) > 5 * 60 {
                return "Paused · last update \(when)"
            }
            if needsReload {
                return "Linked · reload the add-on in Chrome to finish updating"
            }
            return "Linked · \(accounts) account\(accounts == 1 ? "" : "s") · updated \(when)"
        }

        var isHealthy: Bool {
            guard let last = lastSync else { return false }
            return Date().timeIntervalSince(last) <= 5 * 60 && !needsReload
        }
    }

    /// How much mail the notch keeps on this Mac.
    struct Storage: Equatable {
        /// Emails in the notch's lists (who from, subject, preview).
        var emails = 0
        var oldest: Date?
        /// Whole emails saved on disk, and the room they take.
        var whole = 0
        var bytes = 0

        /// "1,240 emails going back to 3 Mar 2026 · 310 saved in full (42 MB)".
        func summary(calendar: Calendar = .current) -> String {
            guard emails > 0 else { return "No mail kept yet" }
            var text = "\(Storage.number(emails)) email\(emails == 1 ? "" : "s")"
            if let oldest = oldest {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.locale = Locale(identifier: "en_AU")
                formatter.dateFormat = "d MMM yyyy"
                text += " going back to \(formatter.string(from: oldest))"
            }
            if whole > 0 {
                text += " · \(Storage.number(whole)) saved in full (\(Storage.size(bytes)))"
            }
            return text
        }

        static func number(_ value: Int) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        /// 0 → "0 MB", 734_003 → "0.7 MB", 44_040_192 → "42 MB", 2_362_232_012 → "2.2 GB".
        static func size(_ bytes: Int) -> String {
            let megabytes = Double(bytes) / 1_048_576
            if megabytes >= 1024 { return String(format: "%.1f GB", megabytes / 1024) }
            if megabytes >= 10 || megabytes == 0 { return String(format: "%.0f MB", megabytes) }
            return String(format: "%.1f MB", megabytes)
        }
    }

    @Published var build = 0
    @Published var update: UpdateStatus = .idle
    @Published var lastUpdateCheck: Date?
    @Published var accounts: [Account] = []
    @Published var link = LinkStatus()
    @Published var storage = Storage()

    private static let wholeLimitKey = "wholeEmailLimit"
    /// How many whole emails to keep on disk; 0 keeps them all.
    @Published var wholeEmailLimit: Int = AppSettings.savedWholeLimit() {
        didSet {
            guard wholeEmailLimit != oldValue else { return }
            UserDefaults.standard.set(wholeEmailLimit, forKey: AppSettings.wholeLimitKey)
            onStorageLimitChanged?()
        }
    }

    private static func savedWholeLimit() -> Int {
        guard let saved = UserDefaults.standard.object(forKey: wholeLimitKey) as? Int,
              WholeEmailStore.limits.contains(saved) else { return WholeEmailStore.standardLimit }
        return saved
    }

    // MARK: Theme

    /// The colours everything is drawn in.
    @Published var theme: ThemeChoice = ThemeChoice.saved() {
        didSet {
            guard theme != oldValue else { return }
            palette = theme == .custom ? customTheme.palette : theme.palette
            UserDefaults.standard.set(theme.rawValue, forKey: ThemeChoice.key)
        }
    }

    /// The theme you make yourself: its colours apply while "Your own" is the theme.
    @Published var customTheme: CustomTheme = CustomTheme.load() {
        didSet {
            guard customTheme != oldValue else { return }
            customTheme.save()
            customThemeEditedAt = Date()
            if theme == .custom {
                palette = customTheme.palette
            }
        }
    }

    /// When your own theme was last changed. The notch redraws itself after each change;
    /// Settings uses this to come back to the editor, not the top of the page.
    private(set) var customThemeEditedAt = Date.distantPast

    var customThemeJustEdited: Bool { Date().timeIntervalSince(customThemeEditedAt) < 1.5 }

    /// The chosen theme's colours, worked out once when it's chosen.
    private(set) var palette: ThemePalette = ThemeChoice.saved().palette

    /// Changes whenever the colours do, so the notch draws itself again.
    var lookID: String {
        theme == .custom ? "custom-" + customTheme.stamp : theme.rawValue
    }

    // MARK: The primary menu

    /// Which tools have a tile on the primary menu, and in what order.
    @Published var homeMenu: HomeMenu = HomeMenu(defaults: .standard) {
        didSet {
            guard homeMenu != oldValue else { return }
            homeMenu.save(in: .standard)
            onHomeMenuChanged?()
        }
    }

    var onHomeMenuChanged: (() -> Void)?

    func moveTile(_ tile: HomeTile, by offset: Int) {
        var menu = homeMenu
        if menu.move(tile, by: offset, amongShown: false) {
            homeMenu = menu
        }
    }

    func setTile(_ tile: HomeTile, shown: Bool) {
        var menu = homeMenu
        if menu.setShown(tile, shown) {
            homeMenu = menu
        } else {
            // The last tile can't go: put its switch back.
            objectWillChange.send()
        }
    }

    // MARK: Extras

    /// The Mac extras, each of which can be switched off.
    enum Extra: String, CaseIterable {
        case nowPlaying
        case focus
        case clipboard
        case shelf

        var key: String { "extra." + rawValue }
    }

    @Published var showsNowPlaying: Bool = AppSettings.saved(Extra.nowPlaying.key, otherwise: true) {
        didSet { extraChanged(.nowPlaying, showsNowPlaying, oldValue) }
    }

    @Published var showsFocus: Bool = AppSettings.saved(Extra.focus.key, otherwise: true) {
        didSet { extraChanged(.focus, showsFocus, oldValue) }
    }

    /// Whether the last things you copied are kept (in memory only) to copy again.
    @Published var keepsClipboard: Bool = AppSettings.saved(Extra.clipboard.key, otherwise: true) {
        didSet { extraChanged(.clipboard, keepsClipboard, oldValue) }
    }

    @Published var showsShelf: Bool = AppSettings.saved(Extra.shelf.key, otherwise: true) {
        didSet { extraChanged(.shelf, showsShelf, oldValue) }
    }

    // Volume and brightness at the notch.
    private static let levelsKey = "extra.levels"
    private static let ownLevelsKey = "extra.levels.replaceSystem"

    /// Whether the closed notch shows the volume and brightness for a moment when they change.
    @Published var showsLevels: Bool = AppSettings.saved(AppSettings.levelsKey, otherwise: true) {
        didSet {
            guard showsLevels != oldValue else { return }
            UserDefaults.standard.set(showsLevels, forKey: AppSettings.levelsKey)
            onLevelsChanged?()
        }
    }

    /// Whether the notch takes over the volume and brightness keys, so macOS's own pop-up
    /// doesn't show as well. Needs Accessibility permission.
    @Published var replacesSystemLevels: Bool = AppSettings.saved(AppSettings.ownLevelsKey, otherwise: false) {
        didSet {
            guard replacesSystemLevels != oldValue else { return }
            UserDefaults.standard.set(replacesSystemLevels, forKey: AppSettings.ownLevelsKey)
            onLevelsChanged?()
        }
    }

    private static let steadyLevelsKey = "extra.levels.always"

    /// Whether the volume and brightness stay beside the closed notch all the time, as two
    /// small gauges, and not only for a moment when they change.
    @Published var levelsAlways: Bool = AppSettings.saved(AppSettings.steadyLevelsKey, otherwise: true) {
        didSet {
            guard levelsAlways != oldValue else { return }
            UserDefaults.standard.set(levelsAlways, forKey: AppSettings.steadyLevelsKey)
            onLevelsChanged?()
        }
    }

    var onLevelsChanged: (() -> Void)?

    /// Whether macOS lets Notch Inbox press keys in other apps and take over the volume
    /// keys (Accessibility, in System Settings). Kept up to date by the app.
    @Published var accessibilityAllowed = false
    /// Asks macOS for that permission, or opens the page in System Settings where it's given (set by the app).
    var onAskForAccessibility: (() -> Void)?
    var onCheckAccessibility: (() -> Void)?

    /// Whether any extra is on (the row under the primary menu's tiles shows if so).
    var showsExtras: Bool { showsNowPlaying || showsFocus || keepsClipboard || showsShelf }

    var onExtrasChanged: (() -> Void)?

    private func extraChanged(_ extra: Extra, _ value: Bool, _ before: Bool) {
        guard value != before else { return }
        UserDefaults.standard.set(value, forKey: extra.key)
        onExtrasChanged?()
    }

    // MARK: Earlier mail

    /// How fetching your earlier mail is going, for Settings → Mail.
    @Published var historyNote: String?
    @Published var historyRunning = false
    /// Asks the add-on, once, to list the last month of your inbox (set by the app).
    var onFetchHistory: (() -> Void)?

    // MARK: Agents

    private static let agentsAtOnceKey = "agents.atOnce"
    private static let agentsWebKey = "agents.web"
    private static let agentFoldersKey = "agents.readFolders"
    private static let agentsChimeKey = "agents.chime"
    /// The choices for how many agents work at once.
    static let agentChoices = [1, 2, 3, 4]
    static let standardAgents = 3

    /// How many agents work at the same time; the rest wait their turn.
    @Published var agentsAtOnce: Int = AppSettings.savedAgentsAtOnce() {
        didSet {
            guard agentsAtOnce != oldValue else { return }
            UserDefaults.standard.set(agentsAtOnce, forKey: AppSettings.agentsAtOnceKey)
            onAgentsChanged?()
        }
    }

    /// Whether agents may search the web and read pages.
    @Published var agentsUseWeb: Bool = AppSettings.saved(AppSettings.agentsWebKey, otherwise: true) {
        didSet {
            guard agentsUseWeb != oldValue else { return }
            UserDefaults.standard.set(agentsUseWeb, forKey: AppSettings.agentsWebKey)
        }
    }

    /// Folders of yours that agents may read (and not change), besides their own.
    @Published var agentReadFolders: [String] = UserDefaults.standard.stringArray(forKey: AppSettings.agentFoldersKey) ?? [] {
        didSet {
            guard agentReadFolders != oldValue else { return }
            UserDefaults.standard.set(agentReadFolders, forKey: AppSettings.agentFoldersKey)
        }
    }

    /// Whether there's a chime when an agent finishes.
    @Published var agentsChime: Bool = AppSettings.saved(AppSettings.agentsChimeKey, otherwise: true) {
        didSet {
            guard agentsChime != oldValue else { return }
            UserDefaults.standard.set(agentsChime, forKey: AppSettings.agentsChimeKey)
        }
    }

    /// Whether agents share a team chat with each other, the chief of staff and you.
    @Published var agentsTeamChat: Bool = AppSettings.saved("agents.teamChat", otherwise: true) {
        didSet {
            guard agentsTeamChat != oldValue else { return }
            UserDefaults.standard.set(agentsTeamChat, forKey: "agents.teamChat")
        }
    }

    /// Why the last folder you tried to add wasn't taken, if it wasn't.
    @Published var agentFolderProblem: String?

    var onAgentsChanged: (() -> Void)?
    /// Opens the panel for choosing a folder agents may read (set by the app).
    var onChooseAgentFolder: (() -> Void)?
    /// Shows the folder all the agents' folders are in (set by the app).
    var onShowAgentsFolder: (() -> Void)?

    private static func savedAgentsAtOnce() -> Int {
        guard let saved = UserDefaults.standard.object(forKey: agentsAtOnceKey) as? Int, agentChoices.contains(saved) else {
            return standardAgents
        }
        return saved
    }

    /// Lets agents read a folder, if it's a sensible one to share.
    func addAgentFolder(_ path: String) {
        let folder = AgentFolders.clean(path)
        if let problem = AgentFolders.problem(with: folder, home: NSHomeDirectory(), already: agentReadFolders) {
            agentFolderProblem = problem
            return
        }
        agentFolderProblem = nil
        agentReadFolders.append(folder)
    }

    func removeAgentFolder(_ path: String) {
        agentFolderProblem = nil
        agentReadFolders.removeAll { $0 == path }
    }

    // MARK: Planner

    private static let classroomKey = "plannerReadsClassroom"
    private static let plansStudyKey = "plannerPlansStudy"
    private static let studyDailyKey = "plannerStudyMinutesADay"
    /// The choices for how much study to plan in a day; 0 means as much as fits.
    static let studyChoices = [60, 120, 180, 0]

    /// Whether Google Classroom emails add their assignments to the planner (read on this Mac).
    @Published var classroomHomework: Bool = AppSettings.saved(AppSettings.classroomKey, otherwise: true) {
        didSet {
            guard classroomHomework != oldValue else { return }
            UserDefaults.standard.set(classroomHomework, forKey: AppSettings.classroomKey)
            onPlannerSettingsChanged?()
        }
    }

    /// Whether homework and revision are fitted into free time on the timetable.
    @Published var plansStudy: Bool = AppSettings.saved(AppSettings.plansStudyKey, otherwise: true) {
        didSet {
            guard plansStudy != oldValue else { return }
            UserDefaults.standard.set(plansStudy, forKey: AppSettings.plansStudyKey)
        }
    }

    /// Minutes of study to plan in a day; 0 for as much as fits.
    @Published var studyMinutesADay: Int = AppSettings.savedStudyMinutes() {
        didSet {
            guard studyMinutesADay != oldValue else { return }
            UserDefaults.standard.set(studyMinutesADay, forKey: AppSettings.studyDailyKey)
        }
    }

    private static func saved(_ key: String, otherwise: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? otherwise : UserDefaults.standard.bool(forKey: key)
    }

    private static func savedStudyMinutes() -> Int {
        guard let saved = UserDefaults.standard.object(forKey: studyDailyKey) as? Int, studyChoices.contains(saved) else {
            return StudyPlanner.standardDaily
        }
        return saved
    }

    /// How finding due dates in emails is going, for Settings and the planner.
    struct Finding: Equatable {
        /// Looking through emails right now.
        var busy = false
        /// Emails looked through with the assistant, and what turned up, since the app started.
        var looked = 0
        var found = 0
        /// Emails waiting their turn.
        var waiting = 0
        var lastAt: Date?
        /// Why the last look didn't work, if it didn't.
        var problem: String?

        /// "Looked through 12 emails, found 3 · 4 waiting".
        var summary: String {
            if let problem = problem { return problem }
            var parts: [String] = []
            if looked > 0 {
                parts.append("Looked through \(looked) email\(looked == 1 ? "" : "s"), found \(found == 0 ? "nothing to add" : "\(found) to add")")
            }
            if busy {
                parts.append("looking now")
            } else if waiting > 0 {
                parts.append("\(waiting) waiting")
            }
            return parts.isEmpty ? "Nothing to look through yet" : parts.joined(separator: " · ")
        }
    }

    @Published var finding = Finding()
    /// How many Classroom emails have been read into the planner since the app started.
    @Published var classroomRead = 0

    var onPlannerSettingsChanged: (() -> Void)?

    var onStorageLimitChanged: (() -> Void)?
    /// Settings is showing the storage numbers: work them out afresh.
    var onMeasureStorage: (() -> Void)?

    var onChooseInbox: ((String, InboxChoice) -> Void)?
    var onSetHidden: ((String, Bool) -> Void)?
    /// Moves an account one place up (-1) or down (1) in the order the notch shows them.
    var onMoveAccount: ((String, Int) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    var onSetUpBrowserLink: (() -> Void)?
    var onCopyDebugInfo: (() -> Void)?
    var onShowAddOnFolder: (() -> Void)?
    var onQuit: (() -> Void)?

    func chooseInbox(_ choice: InboxChoice, for account: String) {
        onChooseInbox?(account, choice)
    }

    func moveAccount(_ account: String, by offset: Int) {
        onMoveAccount?(account, offset)
    }

    func setHidden(_ hidden: Bool, for account: String) {
        onSetHidden?(account, hidden)
    }

    func measureStorage() { onMeasureStorage?() }
    func checkForUpdates() { onCheckForUpdates?() }
    func installUpdate() { onInstallUpdate?() }
    func setUpBrowserLink() { onSetUpBrowserLink?() }
    func copyDebugInfo() { onCopyDebugInfo?() }
    func showAddOnFolder() { onShowAddOnFolder?() }
    func quit() { onQuit?() }

    /// The accounts for Settings: every linked one, in the notch's order, marking which
    /// are hidden and which don't fit.
    static func accounts(linked: [String], shown: [String], hidden: Set<String>,
                         choices: (String) -> InboxChoice, unread: [String: Int],
                         colors: [String: UInt32]) -> [Account] {
        let inNotch = Set(shown)
        return linked.map { address in
            Account(id: address, inbox: choices(address), hidden: hidden.contains(address),
                    inNotch: inNotch.contains(address), unread: unread[address] ?? 0, colorHex: colors[address])
        }
    }
}
