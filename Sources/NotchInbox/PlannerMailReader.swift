import Foundation

/// Keeps the planner fed from your mail. Google Classroom's emails are read here on this
/// Mac. If you've turned on finding due dates, emails that mention a deadline are also put
/// to the assistant, a few at a time and never faster than one question every 45 seconds.
final class PlannerMailReader {
    /// The least time between questions to the assistant.
    static let pause: TimeInterval = 45
    /// The most questions in a day, so a flood of mail can't run through your Claude plan.
    static let mostADay = 120

    private let store: PlannerStore
    private let settings: AppSettings
    private let assistant: Assistant

    private var asking = false
    private var lastAsked: Date?
    private var failures = 0
    private var waitUntil: Date?
    private var askedDay: Date?
    private var askedToday = 0

    init(store: PlannerStore, settings: AppSettings, assistant: Assistant) {
        self.store = store
        self.settings = settings
        self.assistant = assistant
    }

    /// Looks through the mail the notch holds for anything new to put in the planner.
    /// - Parameters:
    ///   - haveWhole: emails whose whole text is in memory or on disk.
    ///   - whole: fetches one of those.
    func read(_ messages: [MailMessage], haveWhole: Set<String>, whole: (String) -> LiveMailbox.WholeEmail?, now: Date = Date()) {
        if settings.classroomHomework {
            var changed = 0
            store.change { changed = PlannerMail.readClassroom(messages, haveWhole: haveWhole, whole: whole, into: &$0, now: now) }
            if changed > 0 {
                settings.classroomRead += changed
            }
        }
        findDueDates(messages, haveWhole: haveWhole, whole: whole, now: now)
    }

    private func findDueDates(_ messages: [MailMessage], haveWhole: Set<String>, whole: (String) -> LiveMailbox.WholeEmail?, now: Date) {
        guard assistant.findsDueDates else {
            // Turned off: nothing is waiting, and any old trouble is forgotten.
            failures = 0
            waitUntil = nil
            show { $0 = AppSettings.Finding(looked: $0.looked, found: $0.found, lastAt: $0.lastAt) }
            return
        }
        guard assistant.status.isReady, !asking else { return }
        if let wait = waitUntil, now < wait { return }
        if let last = lastAsked, now.timeIntervalSince(last) < PlannerMailReader.pause { return }
        let today = Calendar.current.startOfDay(for: now)
        if askedDay != today {
            askedDay = today
            askedToday = 0
        }
        guard askedToday < PlannerMailReader.mostADay else { return }

        var batch: [DueDateFinder.Email] = []
        var wholeIDs: Set<String> = []
        var waiting = 0
        store.change { planner in
            let next = PlannerMail.nextForAssistant(messages, haveWhole: haveWhole, whole: whole, planner: &planner, now: now)
            batch = next.batch
            wholeIDs = next.whole
            waiting = next.waiting
        }
        guard !batch.isEmpty else {
            show { status in
                status.waiting = 0
                status.busy = false
            }
            return
        }

        asking = true
        lastAsked = now
        askedToday += 1
        show { status in
            status.waiting = waiting
            status.busy = true
        }
        var links: [String: URL] = [:]
        for message in messages {
            if let link = message.link {
                links[message.id] = link
            }
        }
        let system = DueDateFinder.system(now: now)
        let prompt = DueDateFinder.prompt(for: batch)
        let asked = batch
        let askedWhole = wholeIDs
        let askedLinks = links
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.assistant.complete(system: system, prompt: prompt)
            await MainActor.run {
                self.answered(result, batch: asked, whole: askedWhole, links: askedLinks)
            }
        }
    }

    private func answered(_ result: Result<String, Assistant.Problem>, batch: [DueDateFinder.Email], whole: Set<String>, links: [String: URL]) {
        asking = false
        let now = Date()
        switch result {
        case .success(let reply):
            // An answer that can't be read counts as nothing found, rather than asking forever.
            let found = DueDateFinder.read(reply, emails: batch, now: now) ?? []
            var added = 0
            store.change { added = PlannerMail.finish(batch, whole: whole, found: found, links: links, planner: &$0, now: now) }
            failures = 0
            waitUntil = nil
            show { status in
                status.busy = false
                status.looked += batch.count
                status.found += added
                status.lastAt = now
                status.problem = nil
            }
        case .failure(let problem):
            // Wait longer each time it goes wrong: 5 minutes, 10, 20, up to an hour.
            failures += 1
            let wait = min(3600, 300 * pow(2, Double(min(failures, 6) - 1)))
            waitUntil = now.addingTimeInterval(wait)
            show { status in
                status.busy = false
                status.lastAt = now
                status.problem = "Couldn't look through your emails: \(problem.message)"
            }
        }
    }

    private func show(_ change: (inout AppSettings.Finding) -> Void) {
        var status = settings.finding
        change(&status)
        if settings.finding != status {
            settings.finding = status
        }
    }
}
