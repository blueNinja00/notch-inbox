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
    case gmail
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .accounts: return "Mail accounts"
        case .assistant: return "Assistant"
        case .timetable: return "Timetable"
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

    var onStorageLimitChanged: (() -> Void)?
    /// Settings is showing the storage numbers: work them out afresh.
    var onMeasureStorage: (() -> Void)?

    var onChooseInbox: ((String, InboxChoice) -> Void)?
    var onSetHidden: ((String, Bool) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    var onSetUpBrowserLink: (() -> Void)?
    var onCopyDebugInfo: (() -> Void)?
    var onShowAddOnFolder: (() -> Void)?
    var onQuit: (() -> Void)?

    func chooseInbox(_ choice: InboxChoice, for account: String) {
        onChooseInbox?(account, choice)
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
