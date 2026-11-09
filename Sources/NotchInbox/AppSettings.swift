import Foundation
#if canImport(Combine)
import Combine
#endif

/// Where Settings opens to, and its sections down the left side.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case accounts
    case assistant
    case gmail
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .accounts: return "Mail accounts"
        case .assistant: return "Assistant"
        case .gmail: return "Gmail link"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .accounts: return "tray.2"
        case .assistant: return "sparkles"
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

    @Published var build = 0
    @Published var update: UpdateStatus = .idle
    @Published var lastUpdateCheck: Date?
    @Published var accounts: [Account] = []
    @Published var link = LinkStatus()

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
