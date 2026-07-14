import Foundation

/// The user's adherence STREAK — how many scheduled doses in a row they've taken without a
/// miss, plus the longest such run they've ever had. Powers the Home reward layer.
///
/// Framing (deliberate): this rewards *consistency with the protocol the user chose* — a
/// record-keeping virtue — never "take more." A streak grows only as scheduled doses are
/// fulfilled and breaks the moment a scheduled dose is missed. It reuses
/// `AdherenceCalculator`'s "taken = a dose logged on that calendar day" rule so the streak and
/// the adherence % never disagree about what counts.
public enum StreakCalculator {

    /// One past-due scheduled dose and whether it was taken. A dose scheduled for *today* that
    /// hasn't been logged yet is PENDING — it is neither taken nor missed, so it is excluded
    /// entirely (it must never break a streak before the day is over).
    public struct DoseEvent: Sendable, Equatable {
        public let date: Date
        public let taken: Bool
        public init(date: Date, taken: Bool) {
            self.date = date
            self.taken = taken
        }
    }

    public struct Result: Sendable, Equatable {
        /// Consecutive taken doses ending at the most recent event — stops at the first miss.
        public let current: Int
        /// The longest consecutive-taken run anywhere in the history.
        public let longest: Int
        public init(current: Int, longest: Int) {
            self.current = current
            self.longest = longest
        }
        public static let zero = Result(current: 0, longest: 0)
    }

    /// Milestone thresholds (in doses) that earn a one-time celebration.
    public static let milestones: [Int] = [7, 30, 90]

    /// The highest milestone reached at `streak` doses (0 if none yet).
    public static func earnedMilestone(for streak: Int) -> Int {
        milestones.last { streak >= $0 } ?? 0
    }

    /// Turn one protocol's adherence result into streak events: every past-due scheduled day
    /// (taken or missed), plus today's day only if it was already taken. Future days and a
    /// not-yet-taken today are dropped as pending.
    public static func events(
        from result: AdherenceCalculator.Result,
        asOf: Date,
        calendar: Calendar = .current
    ) -> [DoseEvent] {
        let today = calendar.startOfDay(for: asOf)
        let takenDays = Set(result.takenDates.map { calendar.startOfDay(for: $0) })
        var events: [DoseEvent] = []
        for expected in result.expectedDates {
            let day = calendar.startOfDay(for: expected)
            let taken = takenDays.contains(day)
            if day < today {
                events.append(DoseEvent(date: day, taken: taken))
            } else if day == today && taken {
                events.append(DoseEvent(date: day, taken: true))
            }
            // day == today && !taken → pending (skip); day > today → not due (skip)
        }
        return events
    }

    /// Current + longest streak over a merged, cross-protocol set of dose events. Events are
    /// sorted chronologically first, so callers can concatenate several protocols' events in
    /// any order. Same-day events each count individually ("no protocol missed": every
    /// scheduled dose that came due must have been taken).
    public static func compute(events: [DoseEvent]) -> Result {
        guard !events.isEmpty else { return .zero }
        let sorted = events.sorted { $0.date < $1.date }

        var longest = 0
        var run = 0
        for event in sorted {
            if event.taken {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }

        var current = 0
        for event in sorted.reversed() {
            if event.taken { current += 1 } else { break }
        }

        return Result(current: current, longest: longest)
    }
}
