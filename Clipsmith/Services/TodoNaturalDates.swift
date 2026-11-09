import Foundation

/// `@due(tomorrow)` → `@due(2026-11-10)` and the `@every(...)` arithmetic.
/// The file only ever stores ISO dates, so it stays standard TaskPaper and
/// the string comparisons the Today view relies on keep working.
enum TodoNaturalDates {

    private static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    /// ISO date for `today`, `tomorrow`, a weekday (`fri`, `friday`: the next
    /// one after today), or `+3d` / `+2w` / `+1m`. Nil when unrecognized
    /// (ISO dates included: those are left as they are).
    static func resolve(_ value: String, today: Date = .now, calendar: Calendar = .current) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        let start = calendar.startOfDay(for: today)
        func iso(_ d: Date?) -> String? { d.map { TodoDates.dateString(from: $0) } }
        switch v {
        case "today": return iso(start)
        case "tomorrow": return iso(calendar.date(byAdding: .day, value: 1, to: start))
        default: break
        }
        if let index = weekdays.firstIndex(where: { v == $0 || (v.count > 3 && v.hasPrefix($0) && fullWeekday($0).hasPrefix(v)) }) {
            let current = calendar.component(.weekday, from: start) - 1
            let ahead = (index - current + 7) % 7
            return iso(calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: start))
        }
        if v.hasPrefix("+"), let (n, unit) = amount(String(v.dropFirst())) {
            return iso(calendar.date(byAdding: unit, value: n, to: start))
        }
        return nil
    }

    /// Rewrites every `@due(<natural>)` in a line; everything else untouched.
    static func normalizingDue(in line: String, today: Date = .now, calendar: Calendar = .current) -> String {
        line.replacing(/@due\(([^()]*)\)/) { match in
            resolve(String(match.output.1), today: today, calendar: calendar)
                .map { "@due(\($0))" } ?? String(match.output.0)
        }
    }

    /// The next due date for `@every(day|week|month|year|3d|2w|1m)`, counted
    /// from `due` (ISO). Nil for an unknown interval or a bad date.
    static func advance(_ due: String, every interval: String, calendar: Calendar = .current) -> String? {
        let parts = due.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let v = interval.trimmingCharacters(in: .whitespaces).lowercased()
        let named: [String: (Int, Calendar.Component)] = [
            "day": (1, .day), "daily": (1, .day), "week": (1, .weekOfYear), "weekly": (1, .weekOfYear),
            "month": (1, .month), "monthly": (1, .month), "year": (1, .year), "yearly": (1, .year),
        ]
        guard let (n, unit) = named[v] ?? amount(v), n > 0 else { return nil }
        return calendar.date(byAdding: unit, value: n, to: date).map { TodoDates.dateString(from: $0) }
    }

    /// "3d" → (3, .day); also w (weeks), m (months), y (years).
    private static func amount(_ s: String) -> (Int, Calendar.Component)? {
        guard let unit = s.last, let n = Int(s.dropLast()) else { return nil }
        switch unit {
        case "d": return (n, .day)
        case "w": return (n, .weekOfYear)
        case "m": return (n, .month)
        case "y": return (n, .year)
        default: return nil
        }
    }

    private static func fullWeekday(_ short: String) -> String {
        ["sun": "sunday", "mon": "monday", "tue": "tuesday", "wed": "wednesday",
         "thu": "thursday", "fri": "friday", "sat": "saturday"][short] ?? short
    }
}
