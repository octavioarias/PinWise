import Foundation

/// Projects how much of a vial remains and when it will run out, so the app can
/// fire "low stock — reorder" alerts. This directly answers a top community request:
/// "how many doses do I have left / when do I run out?".
public enum InventoryEstimator {

    public struct Projection: Codable, Hashable, Sendable {
        public let dosesRemaining: Double
        public let wholeDosesRemaining: Int
        /// Days of supply given the protocol cadence, or `nil` for as-needed protocols.
        public let daysOfSupply: Double?
        /// Projected empty date given the cadence, or `nil` if not derivable.
        public let projectedRunOutDate: Date?
        /// True once remaining supply falls at/under the reorder threshold.
        public let needsReorder: Bool
        /// Cost per dose when the vial has a recorded cost, else `nil`.
        public let costPerDose: Decimal?
    }

    /// - Parameters:
    ///   - vial: the (reconstituted) vial.
    ///   - dose: per-injection dose.
    ///   - dosesTaken: how many doses already drawn from this vial.
    ///   - schedule: cadence used to project days-of-supply / run-out date.
    ///   - reorderThresholdDoses: fire the reorder flag when whole doses remaining ≤ this.
    ///   - referenceDate: "now" for the run-out projection (injected for testability).
    public static func project(
        vial: Vial,
        dose: Mass,
        dosesTaken: Int,
        schedule: DoseSchedule,
        reorderThresholdDoses: Int = 3,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Projection {
        let totalMcg = vial.mass.micrograms
        let perDose = max(dose.micrograms, .leastNonzeroMagnitude)
        let takenMcg = Double(max(0, dosesTaken)) * perDose
        let remainingMcg = max(0, totalMcg - takenMcg)

        let dosesRemaining = remainingMcg / perDose
        let wholeRemaining = Int(dosesRemaining.rounded(.down))

        // Days of supply from doses/day implied by the schedule.
        let dosesPerDay: Double
        switch schedule.kind {
        case .daily: dosesPerDay = 1
        case .everyNDays: dosesPerDay = 1.0 / Double(max(1, schedule.intervalDays))
        case .weekly, .specificWeekdays: dosesPerDay = Double(max(1, schedule.weekdays.count)) / 7.0
        case .asNeeded: dosesPerDay = 0
        }

        let daysOfSupply: Double?
        let runOut: Date?
        if dosesPerDay > 0 {
            let days = dosesRemaining / dosesPerDay
            daysOfSupply = days
            runOut = calendar.date(byAdding: .day, value: Int(days.rounded()), to: referenceDate)
        } else {
            daysOfSupply = nil
            runOut = nil
        }

        var costPerDose: Decimal?
        if let cost = vial.cost {
            let exactDoses = totalMcg / perDose
            if exactDoses > 0 {
                costPerDose = cost / Decimal(exactDoses)
            }
        }

        return Projection(
            dosesRemaining: dosesRemaining,
            wholeDosesRemaining: wholeRemaining,
            daysOfSupply: daysOfSupply,
            projectedRunOutDate: runOut,
            needsReorder: wholeRemaining <= reorderThresholdDoses,
            costPerDose: costPerDose
        )
    }
}
