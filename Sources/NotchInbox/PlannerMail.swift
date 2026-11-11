import Foundation

/// Getting homework and exams out of your mail and into the planner: which emails still
/// need a look, what they say, and what to do about it. Google Classroom's emails are read
/// right here, with no AI. Other emails are only read by the assistant if you turn that on,
/// and only the ones that mention something like a due date.
enum PlannerMail {
    /// Classroom emails older than this are left alone.
    static let classroomLookBack: TimeInterval = 45 * 24 * 3600
    /// Homework with no date from an email older than this isn't worth adding now.
    static let undatedLookBack: TimeInterval = 14 * 24 * 3600
    /// Homework that was due more than this long ago isn't added (you'll have dealt with it).
    static let pastDue: TimeInterval = 2 * 24 * 3600
    /// The assistant waits this long for an email's whole text before reading its preview.
    static let waitForWhole: TimeInterval = 10 * 60

    /// An email's text for reading: its plain text, then its HTML as text (dates are sometimes
    /// only in one of them).
    static func text(of message: MailMessage, whole: LiveMailbox.WholeEmail?) -> (text: String, html: String?, isWhole: Bool) {
        var parts: [String] = []
        var html = message.html
        var isWhole = message.isWhole
        if let whole = whole {
            if !whole.paragraphs.isEmpty { parts.append(whole.paragraphs.joined(separator: "\n")) }
            html = whole.html
            isWhole = true
        } else if !message.body.isEmpty {
            parts.append(message.body.joined(separator: "\n"))
        }
        if let html = html {
            let converted = EmailContent.text(fromHTML: html)
            if !converted.isEmpty { parts.append(converted) }
        }
        return (parts.joined(separator: "\n"), html, isWhole)
    }

    // MARK: Google Classroom

    /// Reads the Classroom emails that haven't been read yet (or were only read as a preview
    /// and are here in full now) into the planner. Returns how many changed it.
    /// - Parameters:
    ///   - haveWhole: emails whose whole text is in memory or on disk.
    ///   - whole: fetches one, from memory or disk.
    @discardableResult
    static func readClassroom(_ messages: [MailMessage], haveWhole: Set<String>, whole: (String) -> LiveMailbox.WholeEmail?,
                              into planner: inout Planner, now: Date = Date(), calendar: Calendar = .current, maxLoads: Int = 25) -> Int {
        var changed = 0
        var loads = 0
        // Oldest first, so a reminder or "returned" finds the assignment that came before it.
        let mine = messages.filter { ClassroomMail.isClassroom($0.senderEmail) && now.timeIntervalSince($0.date) < classroomLookBack }
            .sorted { $0.date < $1.date }
        for message in mine {
            let available = message.isWhole || haveWhole.contains(message.id)
            if let looked = planner.looked(at: message.id), looked.whole || !available { continue }
            var fetched: LiveMailbox.WholeEmail?
            if available && !message.isWhole {
                guard loads < maxLoads else { continue } // next time round
                loads += 1
                fetched = whole(message.id)
            }
            let content = text(of: message, whole: fetched)
            if let notice = ClassroomMail.read(subject: message.subject, text: content.text, html: content.html,
                                               sent: message.date, calendar: calendar), isWorthAdding(notice, sent: message.date, now: now) {
                if ClassroomMail.apply(notice, emailID: message.id, emailLink: message.link, to: &planner, now: now, calendar: calendar) {
                    changed += 1
                }
            }
            planner.markLooked(message.id, whole: content.isWhole, byAssistant: false, now: now)
        }
        return changed
    }

    /// Old news isn't added: homework long past due, or undated homework from weeks ago.
    static func isWorthAdding(_ notice: ClassroomMail.Notice, sent: Date, now: Date) -> Bool {
        switch notice.kind {
        case .returned:
            return true
        case .other:
            return false
        case .assignment, .question, .reminder:
            if let due = notice.due { return now.timeIntervalSince(due) < pastDue }
            return now.timeIntervalSince(sent) < undatedLookBack
        }
    }

    // MARK: Other emails, with the assistant

    /// The next few emails for the assistant to look through, newest first: recent ones that
    /// mention something like a due date and haven't been looked through. Emails that don't
    /// mention one are marked as looked at here and now, and never leave this Mac.
    /// - Returns: the emails to ask about, and how many more are waiting.
    static func nextForAssistant(_ messages: [MailMessage], haveWhole: Set<String>, whole: (String) -> LiveMailbox.WholeEmail?,
                                 planner: inout Planner, now: Date = Date(), calendar: Calendar = .current,
                                 maxLoads: Int = 12) -> (batch: [DueDateFinder.Email], whole: Set<String>, waiting: Int) {
        var batch: [DueDateFinder.Email] = []
        var wholeIDs: Set<String> = []
        var waiting = 0
        var loads = 0
        for message in messages.sorted(by: { $0.date > $1.date }) where now.timeIntervalSince(message.date) < DueDateFinder.lookBack {
            let available = message.isWhole || haveWhole.contains(message.id)
            if let looked = planner.looked(at: message.id), looked.byAssistant, looked.whole || !available { continue }
            // Give the whole email a few minutes to arrive before settling for the preview.
            if !available && now.timeIntervalSince(message.date) < waitForWhole { continue }
            // Classroom's own assignments are already in the planner, read without AI.
            if ClassroomMail.isClassroom(message.senderEmail),
               let notice = ClassroomMail.read(subject: message.subject, text: message.body.joined(separator: "\n"),
                                               sent: message.date, calendar: calendar), notice.kind != .other {
                continue
            }
            // Once there's enough to ask about, the rest wait their turn (counted roughly, by
            // their subject and preview).
            let full = batch.count >= DueDateFinder.batch
            if full || (available && !message.isWhole && loads >= maxLoads) {
                if DueDateFinder.mentionsDeadline(subject: message.subject, text: message.body.joined(separator: "\n")) {
                    waiting += 1
                }
                continue
            }
            var fetched: LiveMailbox.WholeEmail?
            if available && !message.isWhole {
                loads += 1
                fetched = whole(message.id)
            }
            let content = text(of: message, whole: fetched)
            guard DueDateFinder.mentionsDeadline(subject: message.subject, text: content.text) else {
                planner.markLooked(message.id, whole: content.isWhole, byAssistant: true, now: now)
                continue
            }
            batch.append(DueDateFinder.Email(id: message.id, sender: message.sender, subject: message.subject,
                                             sent: message.date, text: content.text))
            if content.isWhole { wholeIDs.insert(message.id) }
        }
        return (batch, wholeIDs, waiting)
    }

    /// The assistant answered: what it found goes in the planner, and the emails count as
    /// looked through. Returns how many things were new.
    @discardableResult
    static func finish(_ batch: [DueDateFinder.Email], whole: Set<String>, found: [DueDateFinder.Found], links: [String: URL],
                       planner: inout Planner, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let added = DueDateFinder.apply(found, links: links, to: &planner, now: now, calendar: calendar)
        for email in batch {
            planner.markLooked(email.id, whole: whole.contains(email.id), byAssistant: true, now: now)
        }
        return added
    }
}
