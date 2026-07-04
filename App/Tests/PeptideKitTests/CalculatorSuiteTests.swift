import Testing
import Foundation
@testable import PeptideKit

@Suite("Mass units")
struct MassTests {
    @Test func conversions() {
        #expect(abs(Mass.mg(5).micrograms - 5000) < 1e-9)
        #expect(abs(Mass.mcg(250).milligrams - 0.25) < 1e-9)
        #expect(abs(Mass.mg(2.5).value(in: .milligram) - 2.5) < 1e-9)
    }

    @Test func displayString() {
        #expect(Mass.mg(5).displayString == "5 mg")
        #expect(Mass.mcg(250).displayString == "250 mcg")
        #expect(Mass.mg(2.5).displayString == "2.50 mg")
    }

    @Test func comparable() {
        #expect(Mass.mcg(500) < Mass.mg(1))
        #expect(max(Mass.mcg(999), Mass.mg(1)) == Mass.mg(1))
    }
}

@Suite("Inventory estimator")
struct InventoryEstimatorTests {
    @Test func weeklyTirzepatideProjection() {
        let vial = Vial(compoundID: UUID(), mass: .mg(10), solventVolumeMilliliters: 1, cost: Decimal(200))
        let ref = TestSupport.day(2026, 7, 4)
        let p = InventoryEstimator.project(
            vial: vial, dose: .mg(2.5), dosesTaken: 1, schedule: .weekly,
            reorderThresholdDoses: 3, referenceDate: ref, calendar: TestSupport.utcCalendar
        )
        #expect(abs(p.dosesRemaining - 3) < 1e-9)      // (10 - 2.5)/2.5
        #expect(p.wholeDosesRemaining == 3)
        #expect(p.needsReorder)                         // 3 <= 3
        #expect(abs((p.daysOfSupply ?? -1) - 21) < 1e-6) // 3 doses / (1/7 per day)
        #expect(p.costPerDose == Decimal(50))           // 200 / 4 exact doses
        #expect(p.projectedRunOutDate == TestSupport.day(2026, 7, 25))
    }

    @Test func asNeededHasNoRunOut() {
        let vial = Vial(compoundID: UUID(), mass: .mg(5), solventVolumeMilliliters: 2)
        let p = InventoryEstimator.project(
            vial: vial, dose: .mcg(250), dosesTaken: 0,
            schedule: DoseSchedule(kind: .asNeeded),
            referenceDate: TestSupport.day(2026, 7, 4), calendar: TestSupport.utcCalendar
        )
        #expect(p.daysOfSupply == nil)
        #expect(p.projectedRunOutDate == nil)
        #expect(p.wholeDosesRemaining == 20)
    }
}

@Suite("Adherence calculator")
struct AdherenceCalculatorTests {
    @Test func dailyWithOneMiss() {
        let cal = TestSupport.utcCalendar
        let logs = [1, 2, 3, 5, 6, 7].map { TestSupport.day(2026, 1, $0) } // missed the 4th
        let r = AdherenceCalculator.evaluate(
            schedule: .daily,
            start: TestSupport.day(2026, 1, 1), end: TestSupport.day(2026, 1, 7),
            logDates: logs, calendar: cal
        )
        #expect(r.expectedCount == 7)
        #expect(r.takenCount == 6)
        #expect(r.missedDates == [TestSupport.day(2026, 1, 4)])
        #expect(abs(r.adherence - 6.0 / 7.0) < 1e-9)
    }

    @Test func everyNDaysExpectedDates() {
        let dates = AdherenceCalculator.expectedDates(
            schedule: .everyNDays(2),
            start: TestSupport.day(2026, 1, 1), end: TestSupport.day(2026, 1, 7),
            calendar: TestSupport.utcCalendar
        )
        #expect(dates == [1, 3, 5, 7].map { TestSupport.day(2026, 1, $0) })
    }

    @Test func weeklyHitsSameWeekdayTwiceInTwoWeeks() {
        let cal = TestSupport.utcCalendar
        let start = TestSupport.day(2026, 1, 5)
        let weekday = cal.component(.weekday, from: start)
        let dates = AdherenceCalculator.expectedDates(
            schedule: .weekdays([weekday]),
            start: start, end: TestSupport.day(2026, 1, 18), calendar: cal
        )
        #expect(dates == [start, TestSupport.day(2026, 1, 12)])
    }
}

@Suite("Titration planner")
struct TitrationPlannerTests {
    @Test func semaglutideEscalation() {
        let cal = TestSupport.utcCalendar
        let steps: [TitrationPlanner.Step] = [
            .weeks(4, dose: .mg(0.25)),
            .weeks(4, dose: .mg(0.5)),
            .weeks(4, dose: .mg(1.0)),
        ]
        #expect(TitrationPlanner.totalDays(steps) == 84)

        let phases = TitrationPlanner.plan(steps: steps, startDate: TestSupport.day(2026, 1, 1), calendar: cal)
        #expect(phases.count == 3)
        #expect(phases[0].startDate == TestSupport.day(2026, 1, 1))
        #expect(phases[0].endDate == TestSupport.day(2026, 1, 29))  // +28 days
        #expect(phases[1].startDate == TestSupport.day(2026, 1, 29))

        // Mid-phase-0 resolves to 0.25 mg; the exclusive end boundary belongs to phase 1.
        #expect(TitrationPlanner.phase(on: TestSupport.day(2026, 1, 15), in: phases)?.dose == .mg(0.25))
        #expect(TitrationPlanner.phase(on: TestSupport.day(2026, 1, 29), in: phases)?.dose == .mg(0.5))
    }
}

@Suite("Site rotation advisor")
struct SiteRotationAdvisorTests {
    @Test func avoidsMostRecentRegion() {
        let compound = UUID()
        let history = [
            DoseLog(compoundID: compound, timestamp: TestSupport.day(2026, 6, 30), dose: .mcg(250), site: .abdomenUpperLeft),
        ]
        let next = SiteRotationAdvisor.suggestNext(history: history)
        #expect(next != nil)
        #expect(next?.region != .abdomen)
    }

    @Test func emptyHistoryReturnsACandidate() {
        #expect(SiteRotationAdvisor.suggestNext(history: []) != nil)
    }

    @Test func picksLeastRecentlyUsedWithinRotation() {
        let c = UUID()
        let history = [
            DoseLog(compoundID: c, timestamp: TestSupport.day(2026, 1, 1), dose: .mcg(250), site: .thighLeft),
            DoseLog(compoundID: c, timestamp: TestSupport.day(2026, 6, 1), dose: .mcg(250), site: .thighRight),
            DoseLog(compoundID: c, timestamp: TestSupport.day(2026, 6, 30), dose: .mcg(250), site: .abdomenUpperLeft),
        ]
        let next = SiteRotationAdvisor.suggestNext(candidates: [.thighLeft, .thighRight], history: history)
        #expect(next == .thighLeft) // less-recently-used of the two thigh sites
    }
}
