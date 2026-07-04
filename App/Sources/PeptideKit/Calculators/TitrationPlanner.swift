import Foundation

/// Builds a dated titration plan from an ordered list of dose steps.
///
/// GLP-1 therapy is defined by escalation (e.g. semaglutide 0.25 → 0.5 → 1.0 → 1.7 → 2.4 mg,
/// typically 4 weeks per step). This turns a template into concrete date ranges the app
/// can schedule reminders around and chart.
public enum TitrationPlanner {

    public struct Step: Codable, Hashable, Sendable {
        public var dose: Mass
        public var durationDays: Int
        public init(dose: Mass, durationDays: Int) {
            self.dose = dose
            self.durationDays = max(1, durationDays)
        }
        /// Convenience for the common "N weeks at this dose" pattern.
        public static func weeks(_ w: Int, dose: Mass) -> Step { Step(dose: dose, durationDays: max(1, w) * 7) }
    }

    public struct Phase: Codable, Hashable, Sendable, Identifiable {
        public var id: Int              // 0-based step index
        public var dose: Mass
        public var startDate: Date
        /// Exclusive end (start of the next phase). For the last phase this is start + duration.
        public var endDate: Date
        public var durationDays: Int
    }

    /// - Parameters:
    ///   - steps: ordered escalation steps.
    ///   - startDate: when phase 0 begins.
    ///   - calendar: injected for deterministic testing.
    public static func plan(
        steps: [Step],
        startDate: Date,
        calendar: Calendar = .current
    ) -> [Phase] {
        var phases: [Phase] = []
        var cursor = calendar.startOfDay(for: startDate)
        for (index, step) in steps.enumerated() {
            let end = calendar.date(byAdding: .day, value: step.durationDays, to: cursor) ?? cursor
            phases.append(Phase(id: index, dose: step.dose, startDate: cursor, endDate: end, durationDays: step.durationDays))
            cursor = end
        }
        return phases
    }

    /// The phase active on a given date, if any.
    public static func phase(on date: Date, in phases: [Phase]) -> Phase? {
        phases.first { date >= $0.startDate && date < $0.endDate }
    }

    /// Total days the full plan spans.
    public static func totalDays(_ steps: [Step]) -> Int {
        steps.reduce(0) { $0 + $1.durationDays }
    }
}
