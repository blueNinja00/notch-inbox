import Foundation
#if canImport(Combine)
import Combine
#endif

/// Everything the notch UI renders from. Starts with sample mail; once the browser
/// add-on delivers real Gmail, `showLive` swaps it in.
final class NotchModel: ObservableObject {
    @Published var level: NotchLevel = .rest
    @Published var metrics: NotchMetrics
    @Published private(set) var accounts: [MailAccount]
    @Published private(set) var messages: [MailMessage]
    @Published private(set) var activeAccountID: String
    @Published private(set) var openMessageID: String?
    @Published private(set) var replyFromID: String?
    @Published var replyText: String = ""
    @Published private(set) var sentFrom: String?

    /// True until real mail arrives from the browser link.
    @Published private(set) var isSample = true
    /// Gmail's own unread counts per account (the feed lists only the newest ~20).
    @Published private(set) var reportedUnread: [String: Int] = [:]

    /// A newer build that's ready to install, if any. Shows as an Update button in the notch.
    @Published var pendingUpdate: Int? = nil
    var onInstallUpdate: (() -> Void)?
    /// Opens a link in the browser (set by the app).
    var onOpenURL: ((URL) -> Void)?

    /// A short update status shown beside the panel buttons after Check for Updates.
    @Published var updateNote: String? = nil

    /// Tells the app you opened a real email, so its whole text is fetched first.
    var onOpenMessage: ((String) -> Void)?

    /// What the browser add-on does about whole emails, for the note under Gmail's previews.
    enum WholeEmails: Equatable {
        /// Fetched within a minute or so.
        case coming
        /// Fetched once you open them here, because Gmail then counts them as read.
        case whenOpened
        /// The browser still runs add-on 1.0, which can't fetch them.
        case addOnNeedsReload
    }

    @Published var wholeEmails: WholeEmails = .coming

    init(provider: MailProvider, metrics: NotchMetrics) {
        let accounts = provider.accounts()
        self.accounts = accounts
        self.messages = provider.messages()
        self.metrics = metrics
        self.activeAccountID = accounts.first?.id ?? ""
    }

    /// Real Gmail arrives read-only: archive, mark unread and reply happen in Gmail.
    var canAct: Bool { isSample }

    /// Swap in real accounts and mail from the browser link.
    func showLive(accounts: [MailAccount], messages: [MailMessage], unread: [String: Int]) {
        let wasSample = isSample
        self.accounts = accounts
        self.messages = messages
        reportedUnread = unread
        isSample = false

        if wasSample || !accounts.contains(where: { $0.id == activeAccountID }) {
            activeAccountID = accounts.first?.id ?? ""
            openMessageID = nil
            replyFromID = nil
            sentFrom = nil
        }
        if let id = openMessageID, !messages.contains(where: { $0.id == id }) {
            openMessageID = nil
        }
        if accounts.isEmpty, level == .detail {
            level = .lanes
        }
    }

    // MARK: Reading

    /// Messages in one inbox, newest first.
    func inbox(_ accountID: String) -> [MailMessage] {
        messages.filter { $0.accountID == accountID }.sorted { $0.date > $1.date }
    }

    func unreadCount(_ accountID: String) -> Int {
        if let reported = reportedUnread[accountID] {
            return reported
        }
        return messages.filter { $0.accountID == accountID && $0.isUnread }.count
    }

    var totalUnread: Int {
        accounts.reduce(0) { $0 + unreadCount($1.id) }
    }

    /// Minimised to the floating mail icon: nothing shows at the notch until you open it.
    @Published var minimised = false
    var onMinimise: ((Bool) -> Void)?

    func setMinimised(_ on: Bool) {
        onMinimise?(on)
    }

    // MARK: Tools and sizes

    /// Which tool the open panel shows. Inboxes and notes both use the lanes and detail sizes.
    enum Tool: Equatable {
        case mail
        case notes
        case assistant
        case timetable
        case settings
    }

    @Published var tool: Tool = .mail
    /// The Settings section showing.
    @Published var settingsSection: SettingsSection = .general
    /// The notes, shared by every screen (set by the app).
    var notesStore: NotesStore?
    @Published var selectedNoteID: UUID?

    /// The timetable, shared by every screen (set by the app).
    var timetableStore: TimetableStore?

    /// What the timetable's side panel is editing.
    enum TimetableEdit: Equatable {
        case lesson(Timetable.Slot)
        case period(UUID)
    }

    @Published var timetableEdit: TimetableEdit? {
        didSet {
            // Finished with a lesson: trim what was typed and drop anything left blank.
            if oldValue != nil && oldValue != timetableEdit {
                timetableStore?.change { $0.tidy() }
            }
        }
    }

    /// Which week of a two-week timetable is on screen: 0 for Week A, 1 for Week B.
    @Published var timetableWeek = 0

    /// Sizes you've dragged each open level to; missing means the standard size.
    @Published var customSizes: [NotchLevel: CGSize] = [:]
    /// Called when you let go after dragging, to remember the size and share it.
    var onResized: (([NotchLevel: CGSize]) -> Void)?

    /// The panel's size at a level: as dragged, else standard.
    func size(_ level: NotchLevel) -> CGSize {
        guard level != .rest, let custom = customSizes[level] else {
            return metrics.bodySize(level, ears: restEars)
        }
        return metrics.clamp(custom, for: level)
    }

    /// The panel's black outline at a level: its size plus the curved shoulders.
    func outline(_ level: NotchLevel) -> CGSize {
        let body = size(level)
        return CGSize(width: body.width + metrics.shoulder(level, ears: restEars) * 2, height: body.height)
    }

    func resize(_ level: NotchLevel, to size: CGSize) {
        guard level != .rest else { return }
        customSizes[level] = metrics.clamp(size, for: level)
    }

    func finishResizing() {
        onResized?(customSizes)
    }

    /// Back to the standard size (double-click the corner grip).
    func resetSize(_ level: NotchLevel) {
        customSizes[level] = nil
        onResized?(customSizes)
    }

    /// Every panel back to its standard size (Settings → General).
    func resetAllSizes() {
        customSizes = [:]
        onResized?(customSizes)
    }

    /// Settings, in the notch: a section per topic down the left.
    func openSettings(_ section: SettingsSection? = nil) {
        if let section = section {
            settingsSection = section
        }
        tool = .settings
        level = .lanes
    }

    func openNotes() {
        tool = .notes
        if selectedNoteID == nil || notesStore?.note(selectedNoteID) == nil {
            selectedNoteID = notesStore?.notes.first?.id
        }
        level = .lanes
    }

    /// The timetable, showing this week, in the bigger panel (a whole day, extracurriculars
    /// included, needs the room).
    func openTimetable() {
        tool = .timetable
        timetableWeek = timetableStore?.timetable.week(of: Date()) ?? 0
        timetableEdit = nil
        level = .detail
    }

    func expandTimetable() {
        tool = .timetable
        level = .detail
    }

    /// Click a lesson (or an empty slot) to edit it; click it again to stop.
    func editLesson(day: Int, period: UUID) {
        let slot = Timetable.Slot(week: timetableWeek, day: day, period: period)
        timetableEdit = timetableEdit == .lesson(slot) ? nil : .lesson(slot)
    }

    func editPeriod(_ id: UUID) {
        timetableEdit = timetableEdit == .period(id) ? nil : .period(id)
    }

    /// A new period after the last one, opened for editing.
    func addPeriod() {
        guard let store = timetableStore else { return }
        var added: UUID?
        store.change { added = $0.addPeriod() }
        if let id = added {
            timetableEdit = .period(id)
        }
    }

    /// The assistant (Claude or Qwen).
    func openAssistant() {
        tool = .assistant
        level = .lanes
    }

    func expandAssistant() {
        tool = .assistant
        level = .detail
    }

    /// Notes in the bigger, detail-sized panel.
    func expandNotes() {
        tool = .notes
        level = .detail
    }

    func newNote() {
        guard let store = notesStore else { return }
        store.removeEmpty(except: nil)
        selectedNoteID = store.add().id
        if tool != .notes || level == .rest || level == .peek {
            tool = .notes
            level = .lanes
        }
    }

    func selectNote(_ id: UUID) {
        notesStore?.removeEmpty(except: id)
        selectedNoteID = id
    }

    /// Width of each ear beside the closed notch: wide enough for every unread count.
    var restEars: CGFloat {
        minimised ? 0 : NotchMetrics.earWidth(for: accounts.map { unreadCount($0.id) })
    }

    func account(_ id: String) -> MailAccount? {
        accounts.first { $0.id == id }
    }

    var activeAccount: MailAccount? { account(activeAccountID) }

    var openMessage: MailMessage? {
        guard let id = openMessageID else { return nil }
        return messages.first { $0.id == id }
    }

    /// The account a reply goes out from: the inbox the mail arrived in, unless you pick another.
    var replyFrom: MailAccount? { account(replyFromID ?? activeAccountID) }

    /// What the hover tiles show: the newest unread message, or else the newest message.
    func headline(_ accountID: String) -> MailMessage? {
        let list = inbox(accountID)
        return list.first { $0.isUnread } ?? list.first
    }

    // MARK: Moving between levels

    /// The primary menu (tools, starting with Mail). Shown by hovering, it closes when the
    /// pointer leaves; opened with a click, it stays until you click somewhere else.
    @Published var homePinned = false

    func peek() {
        if level == .rest {
            homePinned = false
            level = .peek
        }
    }

    func unpeek() {
        if level == .peek && !homePinned { level = .rest }
    }

    /// Opens the primary menu and keeps it open.
    func goHome() {
        homePinned = true
        level = .peek
    }

    /// A click on the hover menu keeps it open.
    func pinHome() {
        if level == .peek { homePinned = true }
    }

    func openLanes() {
        tool = .mail
        level = .lanes
    }

    func back() {
        level = .lanes
    }

    func close() {
        level = .rest
        sentFrom = nil
        homePinned = false
        notesStore?.removeEmpty(except: nil)
        timetableEdit = nil
    }

    /// Expand one inbox, opening the given message (or the newest).
    func open(accountID: String, messageID: String? = nil) {
        tool = .mail
        let target = messageID ?? inbox(accountID).first?.id
        activeAccountID = accountID
        openMessageID = target
        replyFromID = nil
        replyText = ""
        sentFrom = nil
        // Sample mail is marked read here; real mail is read when you open it in Gmail.
        if canAct, let target = target {
            setRead(target, true)
        }
        if !canAct, let target = target {
            onOpenMessage?(target)
        }
        level = .detail
    }

    func open(accountAt index: Int) {
        guard accounts.indices.contains(index) else { return }
        open(accountID: accounts[index].id)
    }

    // MARK: Message actions

    /// Archive the open message and move on to the next one in the same inbox.
    func archiveOpen() {
        guard canAct, let id = openMessageID else { return }
        let before = inbox(activeAccountID)
        guard let index = before.firstIndex(where: { $0.id == id }) else { return }

        messages.removeAll { $0.id == id }

        let after = inbox(activeAccountID)
        let next: MailMessage? = after.isEmpty ? nil : after[min(index, after.count - 1)]
        openMessageID = next?.id
        if let next = next {
            setRead(next.id, true)
        }
        replyFromID = nil
        replyText = ""
        sentFrom = nil
    }

    func markOpenUnread() {
        guard canAct, let id = openMessageID else { return }
        setRead(id, false)
    }

    func chooseReplyAccount(_ id: String) {
        replyFromID = id
    }

    func send() {
        guard canAct, openMessage != nil else { return }
        // Sample data: nothing leaves the Mac. Real replies happen in Gmail.
        sentFrom = replyFrom?.name ?? "your account"
        replyText = ""
    }

    func installUpdate() {
        onInstallUpdate?()
    }


    // MARK: Gmail in the browser

    func openInGmail() {
        if let link = openMessage?.link {
            onOpenURL?(link)
        } else {
            openAccountInGmail(activeAccountID)
        }
    }

    func openAccountInGmail(_ accountID: String) {
        if let url = gmailURL(for: accountID) {
            onOpenURL?(url)
        }
    }

    /// New message in Gmail, from the inbox that's open (or the first account).
    func composeInGmail() {
        let accountID = level == .detail ? activeAccountID : (accounts.first?.id ?? activeAccountID)
        let compose = [URLQueryItem(name: "view", value: "cm"),
                       URLQueryItem(name: "fs", value: "1"),
                       URLQueryItem(name: "tf", value: "1")]
        if let url = gmailURL(for: accountID, extra: compose) {
            onOpenURL?(url)
        }
    }

    /// A link clicked inside an email. Web links open in the browser; email addresses
    /// start a new message in Gmail from the inbox that's open.
    func openLink(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "http", "https":
            onOpenURL?(url)
        case "mailto":
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var compose = [URLQueryItem(name: "view", value: "cm"),
                           URLQueryItem(name: "fs", value: "1"),
                           URLQueryItem(name: "tf", value: "1")]
            if let to = parts?.path, !to.isEmpty {
                compose.append(URLQueryItem(name: "to", value: to))
            }
            for item in parts?.queryItems ?? [] {
                switch item.name.lowercased() {
                case "subject":
                    compose.append(URLQueryItem(name: "su", value: item.value))
                case "body", "cc", "bcc":
                    compose.append(URLQueryItem(name: item.name.lowercased(), value: item.value))
                default:
                    break
                }
            }
            if let link = gmailURL(for: activeAccountID, extra: compose) {
                onOpenURL?(link)
            }
        default:
            break
        }
    }

    /// The line under an email that's still Gmail's short preview.
    func previewNote(for message: MailMessage) -> String {
        if message.couldNotLoad {
            return "Gmail didn't hand over the whole email. Open it in Gmail to read it all."
        }
        switch wholeEmails {
        case .coming:
            return "This is Gmail's preview. The whole email shows here in a moment."
        case .whenOpened:
            return "This is Gmail's preview. The whole email shows here within a minute."
        case .addOnNeedsReload:
            return "This is Gmail's preview. To see whole emails, reload Notch Inbox Link on chrome://extensions, or quit and reopen Chrome."
        }
    }

    func gmailURL(for accountID: String, extra: [URLQueryItem] = []) -> URL? {
        guard let email = account(accountID)?.email else { return nil }
        var components = URLComponents(string: "https://mail.google.com/mail/u/")
        components?.queryItems = [URLQueryItem(name: "authuser", value: email)] + extra
        return components?.url
    }

    private func setRead(_ id: String, _ read: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isUnread = !read
    }
}
