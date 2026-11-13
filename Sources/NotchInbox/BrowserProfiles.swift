import Foundation

/// One of Chrome's profiles (the "people" in its Profiles menu): the folder Chrome keeps it
/// in, the name you gave it, and the Google accounts signed in there.
struct BrowserProfile: Equatable, Identifiable {
    /// The folder's name inside Chrome's data folder: "Default", "Profile 1". It's what
    /// Chrome is told to open, and it doesn't change when you rename the profile.
    let directory: String
    /// Its name in Chrome: yours ("Home"), or Chrome's own ("Person 1").
    let name: String
    /// The account the profile itself is signed in with ("" if none).
    let primary: String
    /// Every Google account signed in on the web in it, the primary one included.
    let emails: [String]
    /// When it was last used, by Chrome's count, to choose between two that both fit.
    let lastActive: Double

    var id: String { directory }

    init(directory: String, name: String, primary: String = "", emails: [String] = [], lastActive: Double = 0) {
        self.directory = directory
        self.name = name
        self.primary = primary
        self.emails = emails
        self.lastActive = lastActive
    }

    /// What it's called in Settings: its name, or its folder's name if it has none.
    var title: String {
        let own = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? directory : own
    }

    func has(_ email: String) -> Bool {
        BrowserProfiles.same(primary, email) || emails.contains { BrowserProfiles.same($0, email) }
    }
}

/// Where the links of one inbox open.
enum LinkPlace: Equatable, Hashable {
    /// In the profile that inbox's address is signed in to, found from Chrome's own list.
    case automatic
    /// In whichever browser window is in front, as links did before profiles were known.
    case front
    /// In the profile you picked, by its folder.
    case profile(String)

    /// As it's kept in the settings: nothing for automatic, "front", or the folder's name.
    init(saved: String?) {
        let value = (saved ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            self = .automatic
        } else if value == LinkPlace.frontKey {
            self = .front
        } else {
            self = .profile(value)
        }
    }

    var saved: String? {
        switch self {
        case .automatic: return nil
        case .front: return LinkPlace.frontKey
        case .profile(let directory): return directory
        }
    }

    static let frontKey = "front"
}

/// Finding the Chrome profile that goes with an inbox, so that a link in an email opens
/// where that address is signed in. Everything here only reads: Chrome's list of profiles,
/// and from each profile's settings nothing but the addresses signed in there.
enum BrowserProfiles {
    // MARK: Reading Chrome's files

    /// The profiles in Chrome's "Local State" file, which lists them under
    /// profile.info_cache by folder name. Guest and system profiles, and ones that are
    /// thrown away when their window closes, are left out.
    static func profiles(localState: Data) -> [BrowserProfile] {
        guard let root = (try? JSONSerialization.jsonObject(with: localState)) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        var found: [BrowserProfile] = []
        for (directory, value) in cache {
            guard isDirectoryName(directory), let info = value as? [String: Any] else { continue }
            if (info["is_ephemeral"] as? Bool) == true || directory == "Guest Profile" || directory == "System Profile" {
                continue
            }
            let name = (info["name"] as? String) ?? ""
            let email = ((info["user_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let active = (info["active_time"] as? NSNumber)?.doubleValue ?? 0
            found.append(BrowserProfile(directory: directory, name: name, primary: email, emails: email.isEmpty ? [] : [email], lastActive: active))
        }
        return found.sorted(by: inOrder)
    }

    /// "Default" first, then "Profile 1", "Profile 2"… by number, as Chrome made them.
    private static func inOrder(_ one: BrowserProfile, _ other: BrowserProfile) -> Bool {
        let first = number(of: one.directory)
        let second = number(of: other.directory)
        return first != second ? first < second : one.directory < other.directory
    }

    private static func number(of directory: String) -> Int {
        if directory == "Default" { return 0 }
        let digits = directory.filter { $0.isNumber }
        return Int(digits) ?? Int.max
    }

    /// The addresses signed in on the web in a profile, from its "Preferences" file, where
    /// Chrome lists them under account_info. Nothing else in the file is looked at.
    static func emails(preferences: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: preferences)) as? [String: Any],
              let accounts = root["account_info"] as? [Any] else { return [] }
        var found: [String] = []
        for entry in accounts {
            guard let account = entry as? [String: Any],
                  let email = (account["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  email.contains("@"), !found.contains(where: { same($0, email) }) else { continue }
            found.append(email)
        }
        return found
    }

    /// Reads a browser's profiles from its data folder: the list from "Local State", and
    /// for each profile the addresses in its "Preferences". A folder that isn't there, or
    /// that can't be read, gives none.
    static func read(folder: URL, fileManager: FileManager = .default) -> [BrowserProfile] {
        guard let state = try? Data(contentsOf: folder.appendingPathComponent("Local State")) else { return [] }
        return profiles(localState: state).map { profile in
            let preferences = folder.appendingPathComponent(profile.directory, isDirectory: true).appendingPathComponent("Preferences")
            guard fileManager.fileExists(atPath: preferences.path), let data = try? Data(contentsOf: preferences) else { return profile }
            var emails = profile.emails
            for email in BrowserProfiles.emails(preferences: data) where !emails.contains(where: { same($0, email) }) {
                emails.append(email)
            }
            return BrowserProfile(directory: profile.directory, name: profile.name, primary: profile.primary, emails: emails, lastActive: profile.lastActive)
        }
    }

    /// Where each browser keeps its profiles, inside ~/Library/Application Support.
    /// (The browsers built on Chrome keep them the same way.)
    static let dataFolders: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
    ]

    static func dataFolder(for browser: String, support: URL) -> URL? {
        guard let path = dataFolders[browser] else { return nil }
        return support.appendingPathComponent(path, isDirectory: true)
    }

    // MARK: Matching an inbox to a profile

    /// Whether two addresses are the same account: whatever their capitals, and for Gmail
    /// addresses whatever dots are in the name (Google treats those as one address).
    static func same(_ one: String, _ other: String) -> Bool {
        let first = canonical(one)
        return !first.isEmpty && first == canonical(other)
    }

    static func canonical(_ email: String) -> String {
        let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = lower.lastIndex(of: "@") else { return lower }
        let name = String(lower[..<at])
        var domain = String(lower[lower.index(after: at)...])
        if domain == "googlemail.com" {
            domain = "gmail.com"
        }
        return (domain == "gmail.com" ? name.replacingOccurrences(of: ".", with: "") : name) + "@" + domain
    }

    /// The profile an inbox's links belong in: the one signed in with that address, or
    /// failing that one where the address is signed in on the web. If more than one fits,
    /// the one used most recently. nil if none does.
    static func profile(for email: String, in profiles: [BrowserProfile]) -> BrowserProfile? {
        let own = profiles.filter { same($0.primary, email) }
        if let best = own.max(by: { $0.lastActive < $1.lastActive }) {
            return best
        }
        let signedIn = profiles.filter { $0.has(email) }
        return signedIn.max(by: { $0.lastActive < $1.lastActive })
    }

    /// The profile a link from an inbox opens in, given what you chose for that inbox.
    /// nil means whichever browser window is in front: you chose that, or nothing fits.
    /// (A profile you picked that has since been deleted falls back to finding one.)
    static func target(for email: String, place: LinkPlace, in profiles: [BrowserProfile]) -> BrowserProfile? {
        switch place {
        case .front:
            return nil
        case .profile(let directory):
            return profiles.first { $0.directory == directory } ?? profile(for: email, in: profiles)
        case .automatic:
            return profile(for: email, in: profiles)
        }
    }

    /// Under an inbox in Settings: where its links open now.
    static func line(for email: String, place: LinkPlace, in profiles: [BrowserProfile]) -> String {
        if place == .front {
            return "Opens in whichever browser window is in front"
        }
        guard let target = target(for: email, place: place, in: profiles) else {
            return profiles.isEmpty ? "Opens in whichever browser window is in front"
                                    : "No profile is signed in with this address, so it opens in whichever window is in front. Pick one to change that."
        }
        if case .profile(let directory) = place, directory != target.directory {
            return "The profile you picked is gone, so it opens in \(title(of: target, among: profiles))"
        }
        return place == .automatic ? "Opens in \(title(of: target, among: profiles)), where it's signed in"
                                   : "Opens in \(title(of: target, among: profiles))"
    }

    /// A profile's name, with its address when two profiles share a name.
    static func title(of profile: BrowserProfile, among profiles: [BrowserProfile]) -> String {
        let shared = profiles.filter { $0.title == profile.title }.count > 1
        return shared && !profile.primary.isEmpty ? "\(profile.title) (\(profile.primary))" : profile.title
    }

    /// Settings' few words on where links open, for the browser there is and how many
    /// profiles it has.
    static func about(browser: String, profiles: Int) -> String {
        if browser.isEmpty {
            return "A link in an email, and Open in Gmail, open in your browser's front window. Opening them in the profile an inbox is signed in to needs Google Chrome, Brave or Edge."
        }
        if profiles <= 1 {
            return "A link in an email, and Open in Gmail, open in \(browser). It has one profile on this Mac, so there's nothing to choose. If you add another (its Profiles menu), each inbox's links will open in the profile that inbox's address is signed in to."
        }
        return "A link in an email, and Open in Gmail, open in the \(browser) profile that inbox's address is signed in to: a link in an email to your home address opens where you're signed in at home. Automatic finds the profile from \(browser)'s own list; pick one yourself if it finds the wrong one. To find them, the notch reads \(browser)'s list of profiles and the addresses signed in to each. That stays on this Mac."
    }

    /// A profile's tooltip in Settings: who's signed in there.
    static func help(for profile: BrowserProfile) -> String {
        profile.emails.isEmpty ? "No Google account is signed in to this profile"
                               : "Signed in here: " + profile.emails.joined(separator: ", ")
    }

    // MARK: Opening

    /// Whether a folder name is one Chrome could have made, and safe to hand back to it:
    /// letters, numbers and spaces only ("Default", "Profile 12").
    static func isDirectoryName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.first?.isLetter == true && name.last != " "
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " ") }
    }

    /// What Chrome is started with to open a web page in one profile. nil for anything
    /// that isn't a web address, or a folder name Chrome wouldn't have made. (Chrome that's
    /// already running takes these from the new copy, opens the page in that profile, and
    /// the new copy quits.)
    static func arguments(for url: URL, directory: String) -> [String]? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host?.isEmpty == false,
              isDirectoryName(directory) else { return nil }
        let address = url.absoluteString
        guard !address.hasPrefix("-") else { return nil }
        return ["--profile-directory=\(directory)", address]
    }
}
