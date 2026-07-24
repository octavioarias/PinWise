import Foundation

/// Projects how much of a vial remains and when it will run out, so the app can
/// fire "low stock — reorder" alerts. This directly answers a top community request:
/// "how many doses do I have left / when do I run out?".
///
/// A vial's usable life is bounded by up to three limits, and they must be reconciled or the
/// numbers don't add up: (1) running out of DOSES, (2) a user-set EXPIRATION date, (3) an advisory
/// BEYOND-USE / discard date after reconstitution. Doses and expiration are HARD limits — whichever
/// is nearest caps the usable-dose count. The beyond-use date is ADVISORY only (community + USP
/// guidance treat the ~28-day mark as a microbial-safety guideline, not a potency cliff), so it is
/// surfaced for a soft "inspect before use" nudge and never reduces usable doses or disables a vial.
public enum InventoryEstimator {

    /// Which HARD limit ends a vial's usable life first. `beyondUse` is intentionally absent — the
    /// beyond-use date is advisory, never a hard cap.
    public enum LimitingFactor: String, Codable, Sendable {
        case doses        // runs out of doses first
        case expiration   // hits the user-set expiration date first
        case none         // as-needed / not derivable
    }

    public struct Projection: Codable, Hashable, Sendable {
        public let dosesRemaining: Double
        public let wholeDosesRemaining: Int
        /// Days of supply given the protocol cadence, or `nil` for as-needed protocols.
        public let daysOfSupply: Double?
        /// Projected empty date from DOSES alone (ignores expiration), or `nil` if not derivable.
        public let projectedRunOutDate: Date?
        /// Whole doses you can STILL take before the nearest HARD limit (doses or expiration).
        /// Equals `wholeDosesRemaining` unless the expiration date cuts the vial short first.
        public let usableWholeDoses: Int
        /// The nearest hard-limit date — earlier of dose run-out and expiration; nil if neither derivable.
        public let effectiveEndDate: Date?
        /// Which hard limit binds at `effectiveEndDate`.
        public let limitingFactor: LimitingFactor
        /// Advisory beyond-use / discard date (reconstitution + window). NOT a hard cap and never
        /// reduces `usableWholeDoses` — surfaced for a soft "inspect before use" nudge only.
        public let beyondUseDate: Date?
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
    ///   - expirationDate: the vial's hard expiration, if set — reconciled with dose run-out.
    ///   - beyondUseDate: advisory discard date (reconstitution + window); echoed, never enforced.
    public static func project(
        vial: Vial,
        dose: Mass,
        dosesTaken: Int,
        schedule: DoseSchedule,
        reorderThresholdDoses: Int = 3,
        referenceDate: Date,
        expirationDate: Date? = nil,
        beyondUseDate: Date? = nil,
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

        // Reconcile the two HARD limits — dose run-out vs. the user-set expiration — into one
        // effective end date + usable-dose count. Beyond-use is advisory and excluded here.
        var usableWhole = wholeRemaining
        var endDate = runOut
        var factor: LimitingFactor = (runOut != nil) ? .doses : .none

        if let exp = expirationDate {
            if exp <= referenceDate {
                usableWhole = 0                       // already expired — unusable regardless of doses
                endDate = exp
                factor = .expiration
            } else if dosesPerDay > 0 {
                let daysToExp = calendar.dateComponents([.day], from: referenceDate, to: exp).day ?? 0
                // +epsilon so an exact boundary (e.g. 14 days × 1/7 = 2.0 stored as 1.9999…) floors
                // correctly instead of losing a dose to floating-point error.
                let dosesByExp = Int((Double(daysToExp) * dosesPerDay + 1e-9).rounded(.down))
                if dosesByExp < wholeRemaining {
                    usableWhole = max(0, dosesByExp)  // expiration cuts the vial short of its doses
                    endDate = exp
                    factor = .expiration
                } else {
                    usableWhole = wholeRemaining       // doses run out on/before expiration
                    endDate = runOut
                    factor = .doses
                }
            } else {
                endDate = exp                         // as-needed: expiration is the only derivable end
                factor = .expiration
            }
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
            usableWholeDoses: usableWhole,
            effectiveEndDate: endDate,
            limitingFactor: factor,
            beyondUseDate: beyondUseDate,
            needsReorder: wholeRemaining <= reorderThresholdDoses,
            costPerDose: costPerDose
        )
    }
}
