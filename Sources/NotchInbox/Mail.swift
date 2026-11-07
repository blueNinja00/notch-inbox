import Foundation

struct MailAccount: Identifiable, Hashable {
    let id: String
    var name: String
    /// Letter shown on the colour badge, so accounts stay distinguishable without colour.
    var letter: String
    var colorHex: UInt32
    /// Number key that jumps to this inbox while the notch is open.
    var shortcut: String
    /// The real address, for accounts linked through the browser (nil for sample accounts).
    var email: String? = nil
}

struct MailMessage: Identifiable, Hashable {
    let id: String
    let accountID: String
    let sender: String
    let subject: String
    /// Paragraphs of plain text: Gmail's preview, or the whole email once it has arrived.
    var body: [String]
    let date: Date
    var isUnread: Bool
    var attachment: String? = nil
    /// Where to open the full message (Gmail), for real mail.
    var link: URL? = nil
    /// The email as its sender designed it, for real HTML mail fetched in full.
    var html: String? = nil
    /// True once the whole email, not just Gmail's preview, is here.
    var isWhole = false
    /// The browser add-on tried to fetch the whole email and couldn't.
    var couldNotLoad = false

    var snippet: String { body.first ?? "" }

    var initials: String {
        sender.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }

    var firstName: String {
        sender.split(separator: " ").first.map { String($0) } ?? sender
    }
}

/// Where accounts and mail come from. The app ships with sample data; a real
/// provider (Apple Mail, Gmail, Outlook, iCloud…) plugs in here later.
protocol MailProvider {
    func accounts() -> [MailAccount]
    func messages() -> [MailMessage]
}

enum MailTime {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// "8:24 am", "Yesterday", "Sun", or "3 Nov".
    static func label(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return clock.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 6 {
            return weekday.string(from: date)
        }
        return dayMonth.string(from: date)
    }
}
