import Foundation

/// Stand-in accounts and mail, matching the design prototype.
struct SampleMailProvider: MailProvider {
    func accounts() -> [MailAccount] {
        [
            MailAccount(id: "personal", name: "Personal", letter: "P", colorHex: 0xF6C26B, shortcut: "1"),
            MailAccount(id: "work", name: "Work", letter: "W", colorHex: 0x4C8DF6, shortcut: "2"),
            MailAccount(id: "studio", name: "Studio", letter: "S", colorHex: 0x3FBF91, shortcut: "3"),
        ]
    }

    func messages() -> [MailMessage] {
        let now = Date()
        func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        return [
            MailMessage(id: "w1", accountID: "work", sender: "Priya Raman", subject: "Q4 roadmap — final review",
                        body: ["Morning! Can you look over section 3 before 2 pm? I’ve left comments on the timeline — mostly around the March launch window.",
                               "Happy to jump on a quick call after standup if that’s easier.",
                               "— Priya"],
                        date: minutesAgo(1), isUnread: true, attachment: "Q4-roadmap-v7.pdf"),
            MailMessage(id: "p1", accountID: "personal", sender: "Mum", subject: "Sunday lunch?",
                        body: ["Thinking yum cha at 12 instead of dinner — can you book for four?",
                               "Dad says the place near the station, not the big one.",
                               "— Mum"],
                        date: minutesAgo(23), isUnread: true),
            MailMessage(id: "w2", accountID: "work", sender: "Tom Walsh", subject: "Re: Client workshop Thursday",
                        body: ["Room’s booked for 10. I’ll bring the prototype on my laptop.",
                               "Could you send the client the agenda by Wednesday?",
                               "— Tom"],
                        date: minutesAgo(30), isUnread: true),
            MailMessage(id: "p2", accountID: "personal", sender: "Sam Chen", subject: "Photos from Saturday",
                        body: ["Album’s up — the harbour ones came out great.",
                               "Grab whichever you want before the link expires on Friday."],
                        date: minutesAgo(44), isUnread: true),
            MailMessage(id: "w3", accountID: "work", sender: "Deploys", subject: "Release 4.12 is on staging",
                        body: ["All checks passed. Promote to production when you’re ready."],
                        date: minutesAgo(55), isUnread: false),
            MailMessage(id: "s1", accountID: "studio", sender: "Ava Lindqvist", subject: "Moodboard feedback",
                        body: ["Love direction B — could we try it with warmer type?",
                               "Happy to pair on it Thursday afternoon if you’re free.",
                               "— Ava"],
                        date: minutesAgo(87), isUnread: true),
            MailMessage(id: "p3", accountID: "personal", sender: "Northside Strata", subject: "Lift maintenance on Thursday",
                        body: ["The east lift will be out of service on Thursday from 9 am to 1 pm while the door sensors are replaced.",
                               "The west lift is unaffected."],
                        date: minutesAgo(60 * 20), isUnread: true),
            MailMessage(id: "w4", accountID: "work", sender: "Lena Fischer", subject: "Offsite agenda — draft",
                        body: ["First pass attached. Shout if I’ve missed anything — especially the Friday afternoon session.",
                               "— Lena"],
                        date: minutesAgo(60 * 22), isUnread: true, attachment: "Offsite-agenda-draft.docx"),
            MailMessage(id: "s2", accountID: "studio", sender: "Kanto Coffee Co.", subject: "Invoice #0042 paid",
                        body: ["Payment received — thanks for the quick turnaround!",
                               "We’ll be in touch about the spring menu boards."],
                        date: minutesAgo(60 * 26), isUnread: true),
            MailMessage(id: "w5", accountID: "work", sender: "People Team", subject: "Timesheets due Friday",
                        body: ["Quick reminder to log this week’s hours by 5 pm Friday."],
                        date: minutesAgo(60 * 28), isUnread: true),
            MailMessage(id: "p4", accountID: "personal", sender: "Harbour Bank", subject: "Your November statement is ready",
                        body: ["The statement for your everyday account is now available in online banking."],
                        date: minutesAgo(60 * 50), isUnread: false),
            MailMessage(id: "s3", accountID: "studio", sender: "Hosting", subject: "Domain renews in 14 days",
                        body: ["Auto-renew is on — nothing to do."],
                        date: minutesAgo(60 * 52), isUnread: false),
        ]
    }
}
