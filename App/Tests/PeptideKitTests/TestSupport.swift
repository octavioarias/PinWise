import Foundation

/// Deterministic calendar/date helpers so date-based tests don't depend on the
/// machine's timezone or the current date.
enum TestSupport {
    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return utcCalendar.date(from: comps)!
    }
}
