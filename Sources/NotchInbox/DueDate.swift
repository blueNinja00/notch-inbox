import Foundation

/// Reads dates the way people (and Google Classroom) write them: "14 Nov", "Nov 14, 11:59 PM",
/// "Friday 4pm", "tomorrow", "20/11", "2026-11-20 16:00". Day comes before month in "20/11",
/// as it does in Australia, unless that can't be right.
enum DueDateParser {
    struct Found: Equatable {
        var date: Date
        /// False when only a day was given: it's due some time that day.
        var hasTime: Bool
    }

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    /// Monday is 0, as on the timetable.
    private static let weekdays: [String: Int] = [
        "mon": 0, "monday": 0, "tue": 1, "tues": 1, "tuesday": 1, "wed": 2, "weds": 2, "wednesday": 2,
        "thu": 3, "thur": 3, "thurs": 3, "thursday": 3, "fri": 4, "friday": 4,
        "sat": 5, "saturday": 5, "sun": 6, "sunday": 6,
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let iso = regex("\\b(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[ t]+(\\d{1,2}):(\\d{2}))?")
    private static let clockAndHalf = regex("\\b(\\d{1,2})[:.](\\d{2})\\s*(am|pm|a\\.m\\.|p\\.m\\.)?")
    private static let hourAndHalf = regex("\\b(\\d{1,2})\\s*(am|pm|a\\.m\\.|p\\.m\\.)(?![a-z])")
    private static let slashed = regex("\\b(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\b")

    /// The date written at the start of `text`, or nil if it doesn't say one. Dates without a
    /// year are the next time that day comes round (or the one just gone, within two months).
    static func parse(_ text: String, relativeTo now: Date, calendar: Calendar = .current) -> Found? {
        var lower = text.lowercased()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
        let whole = { NSRange(lower.startIndex..., in: lower) }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: lower) else { return nil }
            return String(lower[range])
        }
        let today = calendar.startOfDay(for: now)

        // "2026-11-20" or "2026-11-20 16:00".
        if let match = iso?.firstMatch(in: lower, options: [], range: whole()),
           let year = group(match, 1).flatMap({ Int($0) }), let month = group(match, 2).flatMap({ Int($0) }),
           let day = group(match, 3).flatMap({ Int($0) }) {
            let hour = group(match, 4).flatMap { Int($0) }
            let minute = group(match, 5).flatMap { Int($0) }
            return build(year: year, month: month, day: day, minuteOfDay: hour.map { $0 * 60 + (minute ?? 0) }, calendar: calendar)
        }

        // The time of day, taken out so its numbers aren't read as a date.
        var minuteOfDay: Int?
        if lower.range(of: "\\bmidnight\\b", options: .regularExpression) != nil {
            minuteOfDay = 23 * 60 + 59
            lower = lower.replacingOccurrences(of: "midnight", with: " ")
        } else if lower.range(of: "\\b(noon|midday)\\b", options: .regularExpression) != nil {
            minuteOfDay = 12 * 60
            lower = lower.replacingOccurrences(of: "noon", with: " ").replacingOccurrences(of: "midday", with: " ")
        } else if let match = clockAndHalf?.firstMatch(in: lower, options: [], range: whole()),
                  let hour = group(match, 1).flatMap({ Int($0) }), let minute = group(match, 2).flatMap({ Int($0) }),
                  let minutes = clock(hour: hour, minute: minute, half: group(match, 3)) {
            minuteOfDay = minutes
            if let range = Range(match.range, in: lower) { lower.replaceSubrange(range, with: " ") }
        } else if let match = hourAndHalf?.firstMatch(in: lower, options: [], range: whole()),
                  let hour = group(match, 1).flatMap({ Int($0) }),
                  let minutes = clock(hour: hour, minute: 0, half: group(match, 2)) {
            minuteOfDay = minutes
            if let range = Range(match.range, in: lower) { lower.replaceSubrange(range, with: " ") }
        }

        // "20/11" or "20/11/2026".
        if let match = slashed?.firstMatch(in: lower, options: [], range: whole()),
           let first = group(match, 1).flatMap({ Int($0) }), let second = group(match, 2).flatMap({ Int($0) }) {
            let dayFirst = !(first <= 12 && second > 12)
            let day = dayFirst ? first : second
            let month = dayFirst ? second : first
            var year = group(match, 3).flatMap { Int($0) }
            if let short = year, short < 100 { year = 2000 + short }
            return build(year: year ?? nearestYear(month: month, day: day, now: now, calendar: calendar),
                         month: month, day: day, minuteOfDay: minuteOfDay, calendar: calendar)
        }

        // Words and numbers: "fri 20 nov 2026", "november 20th", "tomorrow", "next friday".
        var day: Int?
        var month: Int?
        var year: Int?
        var weekday: Int?
        var offset: Int?
        let words = lower.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { String($0) }
        // Once a date has started, the first word that isn't part of one ends it, so numbers
        // further along ("…essay, 2000 words") aren't read into it.
        var started = false
        for (index, word) in words.prefix(12).enumerated() {
            var isPart = true
            if let found = months[word] {
                if month == nil { month = found }
            } else if let found = weekdays[word] {
                if weekday == nil { weekday = found }
            } else if word == "today" || word == "tonight" {
                offset = offset ?? 0
            } else if word == "tomorrow" || word == "tmrw" || word == "tmr" {
                offset = offset ?? 1
            } else if let number = Int(word.prefix { $0.isNumber }), word.first?.isNumber == true {
                let suffix = String(word.drop { $0.isNumber })
                if !["", "st", "nd", "rd", "th"].contains(suffix) {
                    isPart = false
                } else if suffix.isEmpty && (2000...2100).contains(number) {
                    // A year only counts straight after the day or month.
                    if year == nil && started { year = number } else { isPart = false }
                } else if (1...31).contains(number) && day == nil {
                    // A bare number only counts beside a month ("20 nov", "nov 20").
                    let before = index > 0 ? words[index - 1] : ""
                    let after = index + 1 < words.count ? words[index + 1] : ""
                    if !suffix.isEmpty || months[before] != nil || months[after] != nil {
                        day = number
                    } else {
                        isPart = false
                    }
                } else {
                    isPart = false
                }
            } else {
                isPart = connectors.contains(word) && started
                if !isPart && !started { continue }
            }
            if isPart {
                started = true
            } else if started {
                break
            }
        }

        if let day = day, let month = month {
            return build(year: year ?? nearestYear(month: month, day: day, now: now, calendar: calendar),
                         month: month, day: day, minuteOfDay: minuteOfDay, calendar: calendar)
        }
        if let offset = offset, let date = calendar.date(byAdding: .day, value: offset, to: today) {
            return finish(day: date, minuteOfDay: minuteOfDay, calendar: calendar)
        }
        if let weekday = weekday {
            // The next time that day comes round: "Friday" said on a Friday means next week's.
            let todayIndex = (calendar.component(.weekday, from: today) + 5) % 7
            var ahead = (weekday - todayIndex + 7) % 7
            if ahead == 0 { ahead = 7 }
            if let date = calendar.date(byAdding: .day, value: ahead, to: today) {
                return finish(day: date, minuteOfDay: minuteOfDay, calendar: calendar)
            }
        }
        if minuteOfDay != nil {
            // Just a time: today.
            return finish(day: today, minuteOfDay: minuteOfDay, calendar: calendar)
        }
        return nil
    }

    private static let connectors: Set<String> = ["due", "by", "on", "at", "of", "next", "this", "the", "am", "pm"]
    private static let dayWords: Set<String> = ["today", "tonight", "tomorrow", "tmrw", "tmr", "noon", "midday", "midnight"]
    private static let timeWord = regex("^\\d{1,2}([:.]\\d{2})?(am|pm)?$")
    private static let slashWord = regex("^\\d{1,2}/\\d{1,2}(/\\d{2,4})?$")
    private static let isoWord = regex("^\\d{4}-\\d{1,2}-\\d{1,2}$")
    private static let ordinalWord = regex("^\\d{1,2}(st|nd|rd|th)$")

    /// Whether a word could be part of a date or time: "fri", "20th", "4pm", "tomorrow", "by".
    static func isDateWord(_ word: String) -> Bool {
        let lower = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
        guard !lower.isEmpty else { return false }
        if months[lower] != nil || weekdays[lower] != nil || connectors.contains(lower) || dayWords.contains(lower) { return true }
        if let year = Int(lower), (2000...2100).contains(year) { return true }
        let whole = NSRange(lower.startIndex..., in: lower)
        return [timeWord, slashWord, isoWord, ordinalWord].contains { $0?.firstMatch(in: lower, options: [], range: whole) != nil }
    }

    /// Whether a word is only a joining word ("due", "by", "at"), not a date by itself.
    static func isConnector(_ word: String) -> Bool {
        connectors.contains(word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:")))
    }

    private static func clock(hour: Int, minute: Int, half: String?) -> Int? {
        guard (0...59).contains(minute) else { return nil }
        var hour = hour
        switch half?.first {
        case "a"?:
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
        case "p"?:
            guard (1...12).contains(hour) else { return nil }
            if hour != 12 { hour += 12 }
        default:
            guard (0...23).contains(hour) else { return nil }
        }
        return hour * 60 + minute
    }

    /// The year that puts this day nearest ahead of now, allowing two months back.
    private static func nearestYear(month: Int, day: Int, now: Date, calendar: Calendar) -> Int {
        let thisYear = calendar.component(.year, from: now)
        guard let candidate = calendar.date(from: DateComponents(year: thisYear, month: month, day: day)) else { return thisYear }
        if candidate < now.addingTimeInterval(-60 * 24 * 3600) { return thisYear + 1 }
        if candidate > now.addingTimeInterval(305 * 24 * 3600) { return thisYear - 1 }
        return thisYear
    }

    private static func build(year: Int, month: Int, day: Int, minuteOfDay: Int?, calendar: Calendar) -> Found? {
        guard (1...12).contains(month), (1...31).contains(day), (1990...2200).contains(year),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        return finish(day: date, minuteOfDay: minuteOfDay, calendar: calendar)
    }

    private static func finish(day: Date, minuteOfDay: Int?, calendar: Calendar) -> Found? {
        guard let minutes = minuteOfDay else { return Found(date: calendar.startOfDay(for: day), hasTime: false) }
        guard let date = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day)) else { return nil }
        return Found(date: date, hasTime: true)
    }
}

/// Dates as the planner shows them.
enum DueText {
    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// Whole days from today to the day of `date`: 0 today, 1 tomorrow, −1 yesterday.
    static func days(until date: Date, now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "4 pm", "4:30 pm".
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        ClockTime.hour(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
    }

    /// "Today", "Tomorrow 4 pm", "Fri", "Yesterday", "20 Nov", "20 Nov 2027".
    static func label(for date: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let days = self.days(until: date, now: now, calendar: calendar)
        let day: String
        switch days {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case -1: day = "Yesterday"
        case 2...6: day = formatter("EEE", calendar).string(from: date)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            day = formatter(sameYear ? "d MMM" : "d MMM yyyy", calendar).string(from: date)
        }
        return hasTime ? "\(day) \(time(date, calendar: calendar))" : day
    }

    /// "Fri 20 Nov", with the time if there is one: for lists that are already grouped by day.
    static func full(_ date: Date, hasTime: Bool, calendar: Calendar = .current) -> String {
        let day = formatter("EEE d MMM", calendar).string(from: date)
        return hasTime ? "\(day), \(time(date, calendar: calendar))" : day
    }

    /// What to put in the box when you edit a date; reads back as the same date.
    static func editable(_ date: Date, hasTime: Bool, calendar: Calendar = .current) -> String {
        let day = formatter("d MMM yyyy", calendar).string(from: date)
        guard hasTime else { return day }
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return "\(day) \(ClockTime.long(minutes))"
    }

    /// "today", "tomorrow", "in 6 days", "yesterday", "3 days ago".
    static func countdown(to date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = self.days(until: date, now: now, calendar: calendar)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case let ahead where ahead > 1: return "in \(ahead) days"
        default: return "\(-days) days ago"
        }
    }

    /// 45 → "45 min", 60 → "1 h", 90 → "1 h 30".
    static func length(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60)"
    }
}

/// Homework typed in one line: "Maths worksheet fri 4pm 45m" is a title, when it's due and how
/// long it takes. Anything that doesn't read as a date stays in the title.
enum QuickEntry {
    struct Parsed: Equatable {
        var title: String
        var due: Date?
        var hasTime = false
        var minutes: Int?
    }

    private static let joined = try? NSRegularExpression(pattern: "^(\\d+(?:\\.\\d+)?)(m|min|mins|minutes|h|hr|hrs|hour|hours)$", options: [.caseInsensitive])
    private static let minuteUnits: Set<String> = ["m", "min", "mins", "minute", "minutes"]
    private static let hourUnits: Set<String> = ["h", "hr", "hrs", "hour", "hours"]

    static func parse(_ typed: String, now: Date, calendar: Calendar = .current) -> Parsed {
        let whole = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        var words = whole.split(whereSeparator: { $0.isWhitespace }).map { String($0) }

        // How long it takes: "45m", "1.5h", "45 min", "2 hours".
        var minutes: Int?
        var index = 0
        while index < words.count {
            let word = words[index].lowercased()
            let range = NSRange(word.startIndex..., in: word)
            if let match = joined?.firstMatch(in: word, options: [], range: range),
               let number = Range(match.range(at: 1), in: word).flatMap({ Double(word[$0]) }),
               let unit = Range(match.range(at: 2), in: word).map({ String(word[$0]) }) {
                minutes = length(number, hours: hourUnits.contains(unit))
                words.remove(at: index)
                continue
            }
            if index + 1 < words.count, let number = Double(word),
               minuteUnits.contains(words[index + 1].lowercased()) || hourUnits.contains(words[index + 1].lowercased()) {
                let unit = words[index + 1].lowercased()
                // "4 h" could be a time of day in no language people type; "4 m" neither.
                minutes = length(number, hours: hourUnits.contains(unit))
                words.removeSubrange(index...index + 1)
                continue
            }
            index += 1
        }

        // When it's due: the date words at the end.
        var start = words.count
        while start > 0, DueDateParser.isDateWord(words[start - 1]) {
            start -= 1
        }
        var result = Parsed(title: words.joined(separator: " "), minutes: minutes)
        let tail = Array(words[start...])
        if start > 0, tail.contains(where: { !DueDateParser.isConnector($0) }),
           let found = DueDateParser.parse(tail.joined(separator: " "), relativeTo: now, calendar: calendar) {
            result.title = words[..<start].joined(separator: " ")
            result.due = found.date
            result.hasTime = found.hasTime
        }
        if result.title.isEmpty {
            result = Parsed(title: whole, minutes: nil)
        }
        return result
    }

    private static func length(_ number: Double, hours: Bool) -> Int? {
        let minutes = Int((hours ? number * 60 : number).rounded())
        return (5...600).contains(minutes) ? minutes : nil
    }
}
