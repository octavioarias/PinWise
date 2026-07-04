import Foundation

/// Computes adherence (scheduled vs. actually-logged doses) over a window.
/// Powers the home-screen "adherence %" and the missed-dose insights.
public enum AdherenceCalculator {

    public struct Result: Codable, Hashable, Sendable {
        public let expectedDates: [Date]
        public let takenDates: [Date]
        public let missedDates: [Date]
        public let expectedCount: Int
        public let takenCount: Int
        /// 0.0–1.0. A day counts as adhered if any logged dose falls on it (same calendar day).
        public let adherence: Double
    }

    /// - Parameters:
    ///   - schedule: the protocol cadence.
    ///   - start: window start (inclusive, day granularity).
    ///   - end: window end (inclusive, day granularity).
    ///   - logDates: timestamps of logged doses for this protocol.
    ///   - calendar: injected for deterministic testing (use a fixed UTC calendar in tests).
    public static func evaluate(
        schedule: DoseSchedule,
        start: Date,
        end: Date,
        logDates: [Date],
        calendar: Calendar = .current
    ) -> Result {
        let expected = expectedDates(schedule: schedule, start: start, end: end, calendar: calendar)
        let takenDays = Set(logDates.map { calendar.startOfDay(for: $0) })

        var taken: [Date] = []
        var missed: [Date] = []
        for day in expected {
            if takenDays.contains(day) { taken.append(day) } else { missed.append(day) }
        }
        let adherence = expected.isEmpty ? 1.0 : Double(taken.count) / Double(expected.count)

        return Result(
            expectedDates: expected,
            takenDates: taken,
            missedDates: missed,
            expectedCount: expected.count,
            takenCount: taken.count,
            adherence: adherence
        )
    }

    /// The concrete calendar days a schedule calls for a dose, within [start, end].
    public static func expectedDates(
        schedule: DoseSchedule,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay else { return [] }

        var dates: [Date] = []
        var cursor = startDay
        var step = 0
        // Hard cap to avoid runaway loops on absurd ranges.
        let maxDays = 366 * 20
        while cursor <= endDay && step < maxDays {
            let weekday = calendar.component(.weekday, from: cursor)
            switch schedule.kind {
            case .daily:
                dates.append(cursor)
            case .everyNDays:
                if step % max(1, schedule.intervalDays) == 0 { dates.append(cursor) }
            case .weekly, .specificWeekdays:
                if schedule.weekdays.contains(weekday) { dates.append(cursor) }
            case .asNeeded:
                break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            step += 1
        }
        return dates
    }
}
