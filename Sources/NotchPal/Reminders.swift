import Foundation

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var due: Date
}

// MARK: - Understanding what you typed
// "in 10 min stretch", "remind me in 2h to call mom", "tea at 3:30pm", "tomorrow at 9am standup"

enum ReminderParser {
    static func parse(_ input: String, now: Date = Date()) -> Reminder? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let (due, range) = relative(in: text, now: now)
                                ?? detected(in: text, now: now)
                                ?? clock(in: text, now: now)
        else { return nil }
        text.removeSubrange(range)
        return Reminder(text: clean(text), due: due)
    }

    // "10 min", "in 2h", "after 30 seconds", "in an hour", "half an hour"
    private static let relativePattern = try! NSRegularExpression(
        pattern: #"\b(?:in\s+|after\s+)?(?:(\d+(?:\.\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)|(an?|half\s+an?)\s+(minute|hour))\b"#,
        options: .caseInsensitive)

    // "3pm", "at 3:30 pm", "at 15:30", "at 9"
    private static let clockPattern = try! NSRegularExpression(
        pattern: #"\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\bat\s+(\d{1,2})(?::(\d{2}))?\b"#,
        options: .caseInsensitive)

    private static func relative(in text: String, now: Date) -> (Date, Range<String.Index>)? {
        let ns = NSRange(text.startIndex..., in: text)
        guard let m = relativePattern.firstMatch(in: text, range: ns),
              let range = Range(m.range, in: text) else { return nil }

        let amount: Double
        let unit: String
        if let r = Range(m.range(at: 1), in: text), let u = Range(m.range(at: 2), in: text) {
            amount = Double(text[r]) ?? 0
            unit = text[u].lowercased()
        } else if let r = Range(m.range(at: 3), in: text), let u = Range(m.range(at: 4), in: text) {
            amount = text[r].lowercased().hasPrefix("half") ? 0.5 : 1
            unit = text[u].lowercased()
        } else { return nil }

        let seconds: Double = unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1
        guard amount > 0 else { return nil }
        return (now.addingTimeInterval(amount * seconds), range)
    }

    /// Apple's date detector handles the fancy stuff ("tomorrow at 9am", "friday 5pm").
    private static func detected(in text: String, now: Date) -> (Date, Range<String.Index>)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              var date = m.date,
              let range = Range(m.range, in: text) else { return nil }
        if date <= now { date = date.addingTimeInterval(86_400) }   // "at 9am" when it's already 10am
        guard date > now else { return nil }
        return (date, range)
    }

    private static func clock(in text: String, now: Date) -> (Date, Range<String.Index>)? {
        guard let m = clockPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }

        var hour: Int, minute: Int
        if let h = group(1).flatMap(Int.init) {
            hour = h % 12 + (group(3)?.lowercased() == "pm" ? 12 : 0)
            minute = group(2).flatMap(Int.init) ?? 0
        } else if let h = group(4).flatMap(Int.init) {
            hour = h
            minute = group(5).flatMap(Int.init) ?? 0
        } else { return nil }
        guard hour < 24, minute < 60 else { return nil }

        let cal = Calendar.current
        guard var date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        // "at 3" with no am/pm: take the next 3 o'clock.
        let step: Double = group(4) != nil && hour < 12 ? 43_200 : 86_400
        while date <= now { date = date.addingTimeInterval(step) }
        return (date, range)
    }

    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"^(?:remind\s+me(?:\s+(?:to|that|about))?|to|that|about|and)\b|\b(?:to|and|at|on)$"#,
        options: .caseInsensitive)

    private static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let junk = CharacterSet.whitespaces.union(.punctuationCharacters)
        while true {
            s = s.trimmingCharacters(in: junk)
            let stripped = fillerPattern.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            if stripped == s { break }
            s = stripped
        }
        guard let first = s.first else { return "Time's up!" }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: Showing times

    /// "in 10 min", "at 3:40 PM", "Fri 9:00 AM"
    static func describe(_ due: Date, now: Date = Date()) -> String {
        let s = due.timeIntervalSince(now)
        if s < 3600 { return "in " + duration(Int(s.rounded())) }
        return Calendar.current.isDate(due, inSameDayAs: now) ? "at " + shortTime(due) : dayAndTime(due)
    }

    /// "10 sec", "5 min", "2m 30s", "1h 15m"
    static func duration(_ total: Int) -> String {
        let t = max(1, total), h = t / 3600, m = t % 3600 / 60, s = t % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m) min" }
        return "\(s) sec"
    }

    /// "0:07" / "12:30" when under an hour away, otherwise "3:40 PM".
    static func countdown(to due: Date, now: Date = Date()) -> String {
        let left = Int(due.timeIntervalSince(now).rounded(.up))
        guard left < 3600 else { return shortTime(due) }
        let s = max(0, left)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

// MARK: - Saving between launches

enum ReminderStore {
    private static let key = "reminders"

    static func load() -> [Reminder] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Reminder].self, from: data) else { return [] }
        return list.sorted { $0.due < $1.due }
    }

    static func save(_ list: [Reminder]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
