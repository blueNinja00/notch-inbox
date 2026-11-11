import Foundation

/// Turns Gmail feeds into the notch's accounts and messages, and keeps the notch's own tally
/// of what's unread.
///
/// Gmail's feeds only list unread mail: the newest 20 or so, with a count of all of it. The
/// notch keeps every email it has seen (up to `keep` per account, which goes back a long way),
/// so mail you've read stays in the list, greyed. Whole emails arrive separately from the
/// add-on; the newest few are held in memory and the rest are read from disk when opened.
///
/// Read and unread are the notch's own. Opening an email here marks it read here (Gmail
/// itself isn't changed), any email can be marked unread again, and "Mark all read" clears an
/// inbox, including unread mail too old for Gmail's feed to list. Mail you read in Gmail
/// counts as read here too.
struct LiveMailbox {
    static let maxAccounts = 3
    /// Emails kept per account (who from, subject, preview): years of mail for most inboxes.
    static let keepPerAccount = 10_000
    static let palette: [UInt32] = [0xF6C26B, 0x4C8DF6, 0x3FBF91]
    /// Whole emails asked for per account at a time.
    static let wantPerAccount = 8
    /// How long to wait before asking again for a whole email the add-on couldn't fetch.
    static let retryAfter: TimeInterval = 30 * 60
    /// Whole emails held in memory at once: the ones just fetched or opened.
    static let wholeInMemory = 24

    struct WholeEmail: Codable, Equatable {
        let html: String?
        let paragraphs: [String]
        let attachments: [String]
    }

    /// Account addresses in the order first seen, remembered between launches so
    /// each account keeps its lane and colour.
    private(set) var order: [String]
    /// Gmail's own unread count per account.
    private(set) var unread: [String: Int] = [:]
    /// How many emails to keep per account.
    var keep = LiveMailbox.keepPerAccount
    private var store: [String: MailMessage] = [:]
    /// Every message's ID, newest first.
    private var newestFirst: [String] = []
    private var whole: [String: WholeEmail] = [:]
    private var wholeRecent: [String] = []
    /// Messages whose whole email has been fetched: in memory, or saved on disk.
    private(set) var haveWhole: Set<String> = []
    /// When the add-on last failed to fetch a whole email.
    private var failed: [String: Date] = [:]
    /// Emails you opened in the notch: their whole text is fetched first.
    private var opened: Set<String> = []

    // MARK: What's read here

    /// Emails Gmail has as unread that you read in the notch, and when. Kept between
    /// launches and updates; forgotten once over `readKeep` old and no longer unread in Gmail.
    private(set) var readHere: [String: Date] = [:]
    static let readKeep: TimeInterval = 120 * 24 * 60 * 60
    static let readKeepMost = 5000
    /// Emails you marked unread in the notch, whatever Gmail or "Mark all read" says.
    private var unreadHere: Set<String> = []
    /// "Mark all read" drew a line here: unread mail from before it that Gmail's feed was
    /// too short to list counts as read.
    private var clearedAt: [String: Date] = [:]
    /// What each account's feed lists as unread right now.
    private var listed: [String: Set<String>] = [:]
    /// The listed mail that's from Google, found outside the Primary tab.
    private var extras: [String: Set<String>] = [:]
    /// Mail the notch has that newer mail pushed off the end of Gmail's list: still unread
    /// in Gmail as far as the notch can tell.
    private var beyond: [String: Set<String>] = [:]
    /// How much unread mail Gmail counts that the notch has never seen (older than its list).
    private var unseen: [String: Int] = [:]
    /// How much of that "Mark all read" cleared.
    private var clearedUnseen: [String: Int] = [:]

    /// Before the last "Mark all read" or "Mark all unread", to undo it.
    private struct BulkUndo {
        let account: String
        let ids: Set<String>
        let readHere: [String: Date]
        let unreadHere: Set<String>
        let clearedAt: Date?
        let clearedUnseen: Int
    }

    private var undo: BulkUndo?

    /// Goes up whenever something worth saving changes.
    private(set) var revision = 0

    /// Accounts you chose to keep out of the notch.
    var hidden: Set<String> = []

    init(order: [String] = []) {
        self.order = order
    }

    // MARK: Feeds

    mutating func apply(_ feeds: [GmailFeed], now: Date = Date()) {
        var changed = false
        var resort = false
        for feed in feeds {
            let account = feed.account
            if !order.contains(account) {
                order.append(account)
                changed = true
            }
            if unread[account] != feed.unreadCount {
                unread[account] = feed.unreadCount
                changed = true
            }

            let wasListed = listed[account] ?? []
            let wasExtra = extras[account] ?? []
            let wasMain = wasListed.subtracting(wasExtra)
            let nowListed = Set(feed.entries.map { $0.id })
            let nowExtra = Set(feed.entries.filter { $0.isExtra }.map { $0.id })
            let mainEntries = feed.entries.filter { !$0.isExtra }
            // Unread mail Gmail counts but doesn't list is older than everything it lists.
            let unlisted = max(0, feed.unreadCount - feed.entries.count)
            let cutoff = unlisted > 0 ? mainEntries.map { $0.date }.min() : nil
            let oldCutoff = self.cutoff(for: account)
            let wasUnlisted = (unseen[account] ?? 0) + (beyond[account]?.count ?? 0)
            var far = beyond[account] ?? []
            var cleared = clearedUnseen[account] ?? 0
            let line = clearedAt[account]

            // Mail that left the list was either read (or archived) in Gmail, or pushed off
            // the end by newer mail, in which case it's still unread there. Gmail's count
            // says how many of each: the list lost `gone`, gained `arrivals`, and Gmail's
            // count of unread mail grew by `grew`, so `gone - arrivals + grew` were pushed
            // off. Those are the oldest, and older than everything still listed.
            let gone = wasMain.subtracting(nowListed)
            if !gone.isEmpty, let cutoff = cutoff {
                let arrivals = mainEntries.filter { entry in
                    store[entry.id] == nil && !wasListed.contains(entry.id) && (oldCutoff.map { entry.date > $0 } ?? true)
                }.count
                let grew = (unlisted + mainEntries.count) - (wasUnlisted + wasMain.count)
                let pushed = max(0, gone.count - arrivals + grew)
                let candidates = gone.compactMap { store[$0] }
                    .filter { $0.date < cutoff }
                    .sorted { $0.date != $1.date ? $0.date < $1.date : $0.id > $1.id }
                for message in candidates.prefix(pushed) {
                    far.insert(message.id)
                }
            }

            for entry in feed.entries {
                let known = store[entry.id]
                if known == nil, !entry.isExtra, !wasListed.contains(entry.id), let line = line, entry.date <= line {
                    // It came up from the old unread mail that "Mark all read" had cleared.
                    cleared -= 1
                }
                let message = MailMessage(id: entry.id,
                                          accountID: account,
                                          sender: entry.senderName,
                                          subject: entry.subject,
                                          body: entry.summary.isEmpty ? [] : [entry.summary],
                                          date: entry.date,
                                          isUnread: true,
                                          link: entry.link,
                                          senderEmail: entry.senderEmail)
                if known != message {
                    if known == nil || known?.date != message.date {
                        resort = true
                    }
                    store[entry.id] = message
                    changed = true
                }
            }

            far.subtract(nowListed)
            far = far.filter { store[$0] != nil }
            if far.count > unlisted {
                // Gmail has less unread past the end of its list than that: the oldest were read there.
                let oldestFirst = far.sorted { (store[$0]?.date ?? .distantPast) < (store[$1]?.date ?? .distantPast) }
                far.subtract(oldestFirst.prefix(far.count - unlisted))
            }
            let unknown = unlisted - far.count
            if let line = line, let cutoff = cutoff, cutoff <= line {
                // Everything Gmail doesn't list is from before the line: all of it was cleared.
                cleared = unknown
            }
            cleared = max(0, min(cleared, unknown))

            if wasListed != nowListed || wasExtra != nowExtra || beyond[account] != far
                || unseen[account] != unknown || clearedUnseen[account] != cleared {
                changed = true
            }
            listed[account] = nowListed
            extras[account] = nowExtra
            beyond[account] = far
            unseen[account] = unknown
            clearedUnseen[account] = cleared

            if prune(account) {
                resort = true
                changed = true
            }
        }
        if resort {
            sortMessages()
        }
        if forgetOldReads(now: now) {
            changed = true
        }
        // Whole emails and notes for messages that are gone.
        whole = whole.filter { store[$0.key] != nil }
        wholeRecent = wholeRecent.filter { store[$0] != nil }
        haveWhole = haveWhole.filter { store[$0] != nil }
        failed = failed.filter { store[$0.key] != nil }
        opened = opened.filter { store[$0] != nil }
        if changed {
            revision += 1
        }
    }

    /// Keeps the newest `keep` emails of an account. Returns whether any went.
    private mutating func prune(_ account: String) -> Bool {
        let mine = store.values.filter { $0.accountID == account }
        guard mine.count > keep else { return false }
        let oldestFirst = mine.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id > $1.id }
        for stale in oldestFirst.prefix(mine.count - keep) {
            if beyond[account]?.remove(stale.id) != nil {
                // Still unread in Gmail as far as the notch knows: it joins the mail the notch can't see.
                unseen[account, default: 0] += 1
                if isReadHere(stale.id) {
                    clearedUnseen[account, default: 0] += 1
                }
            }
            readHere[stale.id] = nil
            unreadHere.remove(stale.id)
            store[stale.id] = nil
        }
        return true
    }

    private mutating func sortMessages() {
        newestFirst = store.values
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
            .map { $0.id }
    }

    /// Drops the mail the notch holds for one account (its lane stays), before showing a
    /// narrower part of its inbox, so mail from the old view isn't mistaken for mail
    /// read in Gmail. What you read here stays read.
    mutating func forget(_ account: String) {
        store = store.filter { $0.value.accountID != account }
        listed[account] = nil
        extras[account] = nil
        beyond[account] = nil
        unseen[account] = nil
        clearedUnseen[account] = nil
        if undo?.account == account {
            undo = nil
        }
        sortMessages()
        revision += 1
    }

    /// The account now shows its whole inbox instead of the Primary tab. Its mail stays:
    /// all of it is in the whole inbox too.
    mutating func widen(_ account: String) {
        extras[account] = []
        revision += 1
    }

    /// Every account the browser reported, in their remembered order, shown or not.
    var linkedAccounts: [String] {
        order.filter { unread[$0] != nil }
    }

    /// Up to three accounts that have reported in and aren't hidden, in their remembered order.
    var accounts: [MailAccount] {
        let active = linkedAccounts.filter { !hidden.contains($0) }.prefix(LiveMailbox.maxAccounts)
        return active.enumerated().map { index, email in
            let name = LiveMailbox.label(for: email)
            return MailAccount(id: email,
                               name: name,
                               letter: String(name.prefix(1)).uppercased(),
                               colorHex: LiveMailbox.palette[index % LiveMailbox.palette.count],
                               shortcut: String(index + 1),
                               email: email)
        }
    }

    /// The mail of the accounts in the notch, newest first.
    var messages: [MailMessage] {
        let shown = Set(accounts.map { $0.id })
        var result: [MailMessage] = []
        result.reserveCapacity(newestFirst.count)
        for id in newestFirst {
            guard let stored = store[id], shown.contains(stored.accountID) else { continue }
            result.append(dressed(stored))
        }
        return result
    }

    /// One email as the notch shows it, whichever account it's in.
    func message(_ id: String) -> MailMessage? {
        store[id].map { dressed($0) }
    }

    /// A stored message with its read state, and its whole text if that's in memory.
    private func dressed(_ stored: MailMessage) -> MailMessage {
        var message = stored
        message.isUnread = isUnread(stored)
        guard let email = whole[message.id] else {
            message.couldNotLoad = failed[message.id] != nil
            return message
        }
        message.html = email.html
        if !email.paragraphs.isEmpty {
            message.body = email.paragraphs
        }
        if let first = email.attachments.first {
            let more = email.attachments.count - 1
            message.attachment = more > 0 ? "\(first) and \(more) more" : first
        }
        message.isWhole = true
        return message
    }

    // MARK: Whole emails

    /// Whole emails to ask the add-on for: ones you opened first, then the newest unread,
    /// taking turns between accounts. Ones that failed recently wait a while.
    func wanted(now: Date = Date()) -> [LinkReply.Wanted] {
        var perAccount: [[MailMessage]] = []
        for account in accounts {
            // Unread in Gmail (listed, or pushed off the end of its list), or opened here.
            let ids = (listed[account.id] ?? []).union(beyond[account.id] ?? []).union(opened)
            let candidates = ids.compactMap { id -> MailMessage? in
                guard let message = store[id], message.accountID == account.id, !haveWhole.contains(id) else { return nil }
                guard isUnread(message) || opened.contains(id) else { return nil }
                if let failedAt = failed[id], now.timeIntervalSince(failedAt) <= LiveMailbox.retryAfter { return nil }
                return message
            }
            let ordered = candidates.sorted { a, b in
                let aOpened = opened.contains(a.id)
                let bOpened = opened.contains(b.id)
                if aOpened != bOpened { return aOpened }
                if a.date != b.date { return a.date > b.date }
                return a.id < b.id
            }
            perAccount.append(Array(ordered.prefix(LiveMailbox.wantPerAccount)))
        }

        var picked: [LinkReply.Wanted] = []
        for rank in 0..<LiveMailbox.wantPerAccount {
            for messages in perAccount where rank < messages.count {
                let message = messages[rank]
                picked.append(LinkReply.Wanted(account: message.accountID,
                                               id: message.id,
                                               link: message.link?.absoluteString,
                                               unread: isUnread(message),
                                               opened: opened.contains(message.id)))
            }
        }
        return picked.filter { $0.opened } + picked.filter { !$0.opened }
    }

    /// Takes in a whole email from the add-on. Returns false if it's for a message the
    /// notch no longer has.
    @discardableResult
    mutating func storeWhole(_ upload: EmailUpload, now: Date = Date()) -> Bool {
        guard let message = store[upload.id], message.accountID == upload.account else { return false }
        let html = upload.html.flatMap { EmailContent.cleanHTML($0) }
        let paragraphs = upload.text.map { EmailContent.paragraphs($0) } ?? []
        guard html != nil || !paragraphs.isEmpty else {
            failed[upload.id] = now
            return true
        }
        remember(WholeEmail(html: html, paragraphs: paragraphs, attachments: upload.attachments ?? []), for: upload.id)
        failed[upload.id] = nil
        return true
    }

    /// A whole email that's in memory: just fetched, or read back from disk.
    func wholeInMemory(_ id: String) -> WholeEmail? {
        whole[id]
    }

    /// Holds a whole email in memory to show it (the newest `wholeInMemory` stay).
    mutating func remember(_ email: WholeEmail, for id: String) {
        guard store[id] != nil else { return }
        whole[id] = email
        haveWhole.insert(id)
        wholeRecent.removeAll { $0 == id }
        wholeRecent.append(id)
        while wholeRecent.count > LiveMailbox.wholeInMemory {
            whole[wholeRecent.removeFirst()] = nil
        }
    }

    /// Which whole emails are saved on disk, told once at launch.
    mutating func setSavedWhole(_ ids: Set<String>) {
        haveWhole = ids.filter { store[$0] != nil }.union(whole.keys)
    }

    /// A whole email that should have been on disk wasn't: ask the add-on for it again.
    mutating func lostWhole(_ id: String) {
        guard whole[id] == nil else { return }
        haveWhole.remove(id)
    }

    /// For Copy Debug Info: what the notch holds for one account.
    func stats(for account: String) -> (emails: Int, unread: Int, whole: Int, failed: Int, oldest: Date?) {
        let mine = store.values.filter { $0.accountID == account }
        return (mine.count,
                mine.filter { isUnread($0) }.count,
                mine.filter { haveWhole.contains($0.id) }.count,
                mine.filter { failed[$0.id] != nil }.count,
                mine.map { $0.date }.min())
    }

    /// How much mail the notch keeps, for Settings.
    var history: (emails: Int, oldest: Date?) {
        (store.count, store.values.map { $0.date }.min())
    }

    /// Every message's ID, newest first: which whole emails to keep on disk when space runs out.
    var idsNewestFirst: [String] { newestFirst }

    // MARK: Read and unread, here

    /// Read in the notch: marked read here, or from before the line "Mark all read" drew.
    private func isReadHere(_ id: String) -> Bool {
        if unreadHere.contains(id) { return false }
        if readHere[id] != nil { return true }
        guard let message = store[id], let line = clearedAt[message.accountID] else { return false }
        return message.date <= line
    }

    /// Unread as far as Gmail is known to see it: in its list, or pushed off the end of it.
    private func isUnreadInGmail(_ message: MailMessage) -> Bool {
        listed[message.accountID]?.contains(message.id) == true || beyond[message.accountID]?.contains(message.id) == true
    }

    private func isUnread(_ message: MailMessage) -> Bool {
        if unreadHere.contains(message.id) { return true }
        if isReadHere(message.id) { return false }
        return isUnreadInGmail(message)
    }

    /// You read this email in the notch: it's read here from now on, through restarts and
    /// updates. Returns false if it was already read.
    @discardableResult
    mutating func markReadHere(_ id: String, now: Date = Date()) -> Bool {
        guard let message = store[id], isUnread(message) else { return false }
        unreadHere.remove(id)
        if isUnread(message) {
            readHere[id] = now
        }
        revision += 1
        return true
    }

    /// Marks an email unread in the notch, even one Gmail counts as read. Returns false if
    /// it was already unread.
    @discardableResult
    mutating func markUnreadHere(_ id: String) -> Bool {
        guard let message = store[id], !isUnread(message) else { return false }
        readHere[id] = nil
        if !isUnread(message) {
            unreadHere.insert(id)
        }
        revision += 1
        return true
    }

    /// Everything in an inbox is read: what's listed, and the unread mail Gmail's feed is
    /// too short to list. New mail still arrives unread.
    mutating func markAllRead(_ account: String, now: Date = Date()) {
        guard unread[account] != nil else { return }
        rememberForUndo(account)
        let mine = store.values.filter { $0.accountID == account }
        unreadHere.subtract(mine.map { $0.id })
        for id in (listed[account] ?? []).union(beyond[account] ?? []) {
            readHere[id] = now
        }
        // Unread mail older than Gmail's list is cleared too, and stays cleared if it ever
        // comes up into the list.
        if let cutoff = cutoff(for: account) {
            clearedAt[account] = max(cutoff, clearedAt[account] ?? .distantPast)
        }
        clearedUnseen[account] = unseen[account] ?? 0
        revision += 1
    }

    /// Every email the notch holds for an inbox is unread again, and so is the older unread
    /// mail Gmail counts.
    mutating func markAllUnread(_ account: String) {
        guard unread[account] != nil else { return }
        rememberForUndo(account)
        clearedAt[account] = nil
        clearedUnseen[account] = 0
        for message in store.values where message.accountID == account {
            readHere[message.id] = nil
            if !isUnreadInGmail(message) {
                unreadHere.insert(message.id)
            }
        }
        revision += 1
    }

    /// The account whose last "Mark all read" or "Mark all unread" can be undone.
    var undoAccount: String? { undo?.account }

    /// Puts an inbox's read and unread back as they were before the last "Mark all".
    @discardableResult
    mutating func undoMarkAll() -> Bool {
        guard let saved = undo else { return false }
        readHere = readHere.filter { !saved.ids.contains($0.key) }
        readHere.merge(saved.readHere.filter { store[$0.key] != nil }) { _, before in before }
        unreadHere.subtract(saved.ids)
        unreadHere.formUnion(saved.unreadHere.filter { store[$0] != nil })
        clearedAt[saved.account] = saved.clearedAt
        clearedUnseen[saved.account] = max(0, min(saved.clearedUnseen, unseen[saved.account] ?? 0))
        undo = nil
        revision += 1
        return true
    }

    private mutating func rememberForUndo(_ account: String) {
        let ids = Set(store.values.filter { $0.accountID == account }.map { $0.id })
        undo = BulkUndo(account: account,
                        ids: ids,
                        readHere: readHere.filter { ids.contains($0.key) },
                        unreadHere: unreadHere.intersection(ids),
                        clearedAt: clearedAt[account],
                        clearedUnseen: clearedUnseen[account] ?? 0)
    }

    /// The oldest email Gmail's list reaches back to, when it has more unread than it lists.
    private func cutoff(for account: String) -> Date? {
        guard (unseen[account] ?? 0) + (beyond[account]?.count ?? 0) > 0 else { return nil }
        return (listed[account] ?? []).subtracting(extras[account] ?? []).compactMap { store[$0]?.date }.min()
    }

    /// Unread counts as the notch shows them: Gmail's unread mail that isn't read here, plus
    /// anything you marked unread here.
    var shownUnread: [String: Int] {
        var counts: [String: Int] = [:]
        for account in unread.keys {
            counts[account] = unreadCount(for: account)
        }
        return counts
    }

    func unreadCount(for account: String) -> Int {
        let known = (listed[account] ?? []).union(beyond[account] ?? [])
        var count = known.filter { !isReadHere($0) }.count
        count += max(0, (unseen[account] ?? 0) - (clearedUnseen[account] ?? 0))
        count += unreadHere.filter { !known.contains($0) && store[$0]?.accountID == account }.count
        return count
    }

    /// How many emails the notch remembers you reading here.
    var readHereCount: Int { readHere.count }

    /// Returns whether anything was forgotten.
    private mutating func forgetOldReads(now: Date) -> Bool {
        let before = readHere.count
        var stillUnread = Set<String>()
        for ids in listed.values { stillUnread.formUnion(ids) }
        for ids in beyond.values { stillUnread.formUnion(ids) }
        readHere = readHere.filter { now.timeIntervalSince($0.value) < LiveMailbox.readKeep || stillUnread.contains($0.key) }
        if readHere.count > LiveMailbox.readKeepMost {
            let newest = readHere.sorted { $0.value > $1.value }.prefix(LiveMailbox.readKeepMost)
            readHere = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        return readHere.count != before
    }

    /// You opened this email in the notch: fetch its whole text next, even if it's read.
    mutating func markOpened(_ id: String) {
        guard store[id] != nil else { return }
        opened.insert(id)
        failed[id] = nil // looking at it is worth one more try
    }

    // MARK: Keeping a copy between launches

    /// What the notch held, so it can show your mail the moment the app starts (after an
    /// update, say) instead of waiting for the browser add-on. Whole emails are kept
    /// separately, one file each.
    struct Snapshot: Codable, Equatable {
        struct Message: Codable, Equatable {
            let id: String
            let accountID: String
            let sender: String
            let subject: String
            let preview: String
            let date: Date
            let isUnread: Bool
            let link: URL?
            /// The sender's address (missing in files from before build 28).
            var senderEmail: String? = nil
        }

        var savedAt: Date
        var order: [String]
        var unread: [String: Int]
        var messages: [Message]
        /// What each account was showing (Primary or whole inbox) when this was saved.
        var views: [String: InboxChoice]? = nil
        /// Emails you read in the notch, and when (missing in files from before build 27).
        var readHere: [String: Date]? = nil
        /// What each account's feed listed as unread.
        var listed: [String: [String]]? = nil
        // The rest is missing in files from before build 28.
        var unreadHere: [String]? = nil
        var clearedAt: [String: Date]? = nil
        var extras: [String: [String]]? = nil
        var beyond: [String: [String]]? = nil
        var unseen: [String: Int]? = nil
        var clearedUnseen: [String: Int]? = nil
    }

    func snapshot(at date: Date = Date()) -> Snapshot {
        let messages = newestFirst.compactMap { id -> Snapshot.Message? in
            guard let message = store[id] else { return nil }
            return Snapshot.Message(id: message.id, accountID: message.accountID, sender: message.sender,
                                    subject: message.subject, preview: message.body.first ?? "",
                                    date: message.date, isUnread: isUnread(message), link: message.link,
                                    senderEmail: message.senderEmail.isEmpty ? nil : message.senderEmail)
        }
        return Snapshot(savedAt: date, order: order, unread: unread, messages: messages,
                        readHere: readHere, listed: listed.mapValues { $0.sorted() },
                        unreadHere: unreadHere.sorted(), clearedAt: clearedAt,
                        extras: extras.mapValues { $0.sorted() }, beyond: beyond.mapValues { $0.sorted() },
                        unseen: unseen, clearedUnseen: clearedUnseen)
    }

    init(snapshot: Snapshot) {
        order = snapshot.order
        unread = snapshot.unread
        readHere = snapshot.readHere ?? [:]
        unreadHere = Set(snapshot.unreadHere ?? [])
        clearedAt = snapshot.clearedAt ?? [:]
        listed = (snapshot.listed ?? [:]).mapValues { Set($0) }
        extras = (snapshot.extras ?? [:]).mapValues { Set($0) }
        beyond = (snapshot.beyond ?? [:]).mapValues { Set($0) }
        clearedUnseen = snapshot.clearedUnseen ?? [:]
        for message in snapshot.messages {
            store[message.id] = MailMessage(id: message.id,
                                            accountID: message.accountID,
                                            sender: message.sender,
                                            subject: message.subject,
                                            body: message.preview.isEmpty ? [] : [message.preview],
                                            date: message.date,
                                            isUnread: true,
                                            link: message.link,
                                            senderEmail: message.senderEmail ?? "")
        }
        if let saved = snapshot.unseen {
            unseen = saved
        } else {
            // A copy from before build 28: what Gmail counts beyond what it listed.
            for (account, count) in snapshot.unread {
                unseen[account] = max(0, count - (listed[account]?.count ?? 0))
            }
            if snapshot.listed == nil {
                // Before build 27: unread was saved per message.
                for message in snapshot.messages where message.isUnread {
                    listed[message.accountID, default: []].insert(message.id)
                }
                for (account, count) in snapshot.unread {
                    unseen[account] = max(0, count - (listed[account]?.count ?? 0))
                }
            }
        }
        sortMessages()
    }

    /// A short name for an address until the settings page lets you rename it:
    /// "you@gmail.com" → "you", "z123@ad.unsw.edu.au" → "UNSW", "me@acme-studio.com" → "Acme-studio".
    static func label(for email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map { String($0) }
        guard parts.count == 2, !parts[0].isEmpty else { return email }
        let local = parts[0]
        let domain = parts[1].lowercased()
        if domain == "gmail.com" || domain == "googlemail.com" {
            return local
        }
        let generic: Set<String> = ["com", "net", "org", "edu", "gov", "co", "ac", "au", "uk", "nz",
                                    "io", "me", "info", "biz", "mail", "email"]
        let meaningful = domain.split(separator: ".").map { String($0) }.filter { !generic.contains($0) }
        guard let name = meaningful.last, !name.isEmpty else { return local }
        return name.count <= 4 ? name.uppercased() : name.prefix(1).uppercased() + name.dropFirst()
    }
}
