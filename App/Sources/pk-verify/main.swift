import Foundation
import PeptideKit

// A dependency-free assertion harness that mirrors the swift-testing suite in Tests/.
// Run with `swift run pk-verify`. Exits non-zero if any check fails.

var checks = 0
var failures = 0

@MainActor func check(_ condition: Bool, _ label: String) {
    checks += 1
    if condition {
        print("  ✓ \(label)")
    } else {
        failures += 1
        print("  ✗ FAIL: \(label)")
    }
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) < tol }

@MainActor func section(_ name: String) { print("\n▸ \(name)") }

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
@MainActor func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = m; c.day = d
    return cal.date(from: c)!
}

// MARK: - Reconstitution
section("Reconstitution calculator")
do {
    let r = try ReconstitutionCalculator.calculate(
        ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(250)))
    check(approx(r.concentrationMcgPerMl, 2500), "5mg/2mL ⇒ 2500 mcg/mL")
    check(approx(r.drawVolumeMilliliters, 0.10), "250 mcg ⇒ draw 0.10 mL")
    check(approx(r.syringeUnits, 10), "0.10 mL ⇒ 10 units (U-100)")
    check(r.dosesPerVial == 20, "5mg @ 250mcg ⇒ 20 doses")

    let t = try ReconstitutionCalculator.calculate(
        ReconstitutionInput(vialMass: .mg(10), solventVolumeMilliliters: 1, desiredDose: .mg(2.5)))
    check(approx(t.syringeUnits, 25), "tirz 10mg/1mL @ 2.5mg ⇒ 25 units")
    check(t.dosesPerVial == 4, "tirz 10mg @ 2.5mg ⇒ 4 doses")

    let u40 = try ReconstitutionCalculator.calculate(
        ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(250), syringe: .u40))
    check(approx(u40.syringeUnits, 4), "U-40 barrel reads 4 units for 0.10 mL")

    let frac = try ReconstitutionCalculator.calculate(
        ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(300)))
    check(frac.dosesPerVial == 16, "5mg @ 300mcg ⇒ floor(16.66) = 16 doses")

    let inv = try ReconstitutionCalculator.dose(forUnits: 10, vialMass: .mg(5), solventVolumeMilliliters: 2)
    check(approx(inv.micrograms, 250, 1e-6), "inverse: 10 units ⇒ 250 mcg")
} catch {
    check(false, "unexpected throw: \(error)")
}

@MainActor func expectThrow(_ expected: ReconstitutionError, _ label: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures += 1; print("  ✗ FAIL: \(label) (did not throw)") }
    catch let e as ReconstitutionError where e == expected { print("  ✓ \(label)") }
    catch { failures += 1; print("  ✗ FAIL: \(label) (threw \(error))") }
}
expectThrow(.nonPositiveVialMass, "rejects zero vial mass") {
    _ = try ReconstitutionCalculator.calculate(ReconstitutionInput(vialMass: .mg(0), solventVolumeMilliliters: 2, desiredDose: .mcg(250)))
}
expectThrow(.nonPositiveSolventVolume, "rejects zero solvent") {
    _ = try ReconstitutionCalculator.calculate(ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 0, desiredDose: .mcg(250)))
}
expectThrow(.doseExceedsVialContents, "rejects dose > vial contents") {
    _ = try ReconstitutionCalculator.calculate(ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mg(6)))
}

// MARK: - Mass
section("Mass units")
check(approx(Mass.mg(5).micrograms, 5000), "5 mg == 5000 mcg")
check(approx(Mass.mcg(250).milligrams, 0.25), "250 mcg == 0.25 mg")
check(Mass.mg(5).displayString == "5 mg", "displayString 5 mg")
check(Mass.mcg(250).displayString == "250 mcg", "displayString 250 mcg")
check(Mass.mg(2.5).displayString == "2.50 mg", "displayString 2.50 mg")
check(Mass.mcg(500) < Mass.mg(1), "500 mcg < 1 mg")

// MARK: - Fixed-unit display (the user's chosen mg/mcg must hold regardless of magnitude)
section("Fixed-unit display")
// A dose entered in mg stays mg even below 1 mg (auto would flip it to "500 mcg").
check(Mass.mg(0.5).displayString(in: .milligram) == "0.5 mg", "0.5 mg in mg ⇒ 0.5 mg (not 500 mcg)")
check(Mass.mg(0.5).displayString(in: .microgram) == "500 mcg", "0.5 mg in mcg ⇒ 500 mcg")
// A dose entered in mcg stays mcg even at/above 1000 mcg (auto would flip it to "1.5 mg").
check(Mass.mcg(1500).displayString(in: .microgram) == "1500 mcg", "1500 mcg in mcg ⇒ 1500 mcg (not 1.5 mg)")
check(Mass.mcg(1500).displayString(in: .milligram) == "1.5 mg", "1500 mcg in mg ⇒ 1.5 mg")
// Trailing zeros trimmed; whole numbers show no decimal.
check(Mass.mg(2.5).displayString(in: .milligram) == "2.5 mg", "2.5 mg in mg ⇒ 2.5 mg (trimmed)")
check(Mass.mg(2).displayString(in: .milligram) == "2 mg", "2 mg in mg ⇒ 2 mg (no decimals)")
check(Mass.mcg(250).displayString(in: .microgram) == "250 mcg", "250 mcg in mcg ⇒ 250 mcg")
// Pre-mixed strength entry: a value typed in a chosen unit/mL becomes the right µg/mL concentration.
check(approx(Concentration(microgramsPerMilliliter: Mass(2.5, .milligram).micrograms).milligramsPerMilliliter, 2.5),
      "2.5 entered as mg/mL ⇒ 2.5 mg/mL")
check(approx(Concentration(microgramsPerMilliliter: Mass(500, .microgram).micrograms).microgramsPerMilliliter, 500),
      "500 entered as mcg/mL ⇒ 500 mcg/mL (not 500000)")
check(approx(Mass(0.5, .milligram).value(in: .microgram), 500), "0.5 mg strength reads 500 in mcg")

// MARK: - Inventory
section("Inventory estimator")
do {
    let vial = Vial(compoundID: UUID(), mass: .mg(10), solventVolumeMilliliters: 1, cost: Decimal(200))
    let p = InventoryEstimator.project(
        vial: vial, dose: .mg(2.5), dosesTaken: 1, schedule: .weekly,
        reorderThresholdDoses: 3, referenceDate: day(2026, 7, 4), calendar: cal)
    check(approx(p.dosesRemaining, 3), "10mg − 1×2.5mg ⇒ 3 doses remaining")
    check(p.needsReorder, "3 remaining ≤ threshold 3 ⇒ reorder")
    check(approx(p.daysOfSupply ?? -1, 21, 1e-6), "weekly ⇒ 21 days of supply")
    check(p.costPerDose == Decimal(50), "$200 / 4 doses ⇒ $50/dose")
    check(p.projectedRunOutDate == day(2026, 7, 25), "run-out projected 2026-07-25")

    let prn = InventoryEstimator.project(
        vial: Vial(compoundID: UUID(), mass: .mg(5), solventVolumeMilliliters: 2),
        dose: .mcg(250), dosesTaken: 0, schedule: DoseSchedule(kind: .asNeeded),
        referenceDate: day(2026, 7, 4), calendar: cal)
    check(prn.daysOfSupply == nil && prn.projectedRunOutDate == nil, "as-needed ⇒ no run-out date")
    check(prn.wholeDosesRemaining == 20, "5mg @ 250mcg ⇒ 20 whole doses")
}

// MARK: - Adherence
section("Adherence calculator")
do {
    let logs = [1, 2, 3, 5, 6, 7].map { day(2026, 1, $0) }
    let r = AdherenceCalculator.evaluate(
        schedule: .daily, start: day(2026, 1, 1), end: day(2026, 1, 7), logDates: logs, calendar: cal)
    check(r.expectedCount == 7 && r.takenCount == 6, "daily 7-day window, 6 taken")
    check(r.missedDates == [day(2026, 1, 4)], "missed date is Jan 4")
    check(approx(r.adherence, 6.0 / 7.0), "adherence 6/7")

    let every2 = AdherenceCalculator.expectedDates(
        schedule: .everyNDays(2), start: day(2026, 1, 1), end: day(2026, 1, 7), calendar: cal)
    check(every2 == [1, 3, 5, 7].map { day(2026, 1, $0) }, "every-2-days ⇒ Jan 1,3,5,7")

    let start = day(2026, 1, 5)
    let wd = cal.component(.weekday, from: start)
    let weekly = AdherenceCalculator.expectedDates(
        schedule: .weekdays([wd]), start: start, end: day(2026, 1, 18), calendar: cal)
    check(weekly == [start, day(2026, 1, 12)], "weekly ⇒ 2 hits in 14 days")
}

// MARK: - Adherence grace
section("Adherence grace (late doses)")
do {
    // every-3-days Jan 1/4/7; a single dose logged Jan 2 (1 day late for Jan 1, not itself due).
    let logs = [day(2026, 1, 2)]
    let g0 = AdherenceCalculator.evaluate(schedule: .everyNDays(3), start: day(2026, 1, 1),
                                          end: day(2026, 1, 7), logDates: logs, graceDays: 0, calendar: cal)
    check(g0.takenCount == 0, "grace 0 ⇒ Jan-2 dose doesn't cover Jan-1 (0 taken)")
    let g1 = AdherenceCalculator.evaluate(schedule: .everyNDays(3), start: day(2026, 1, 1),
                                          end: day(2026, 1, 7), logDates: logs, graceDays: 1, calendar: cal)
    check(g1.takenCount == 1 && g1.takenDates == [day(2026, 1, 1)], "grace 1 ⇒ Jan-2 covers Jan-1 late")
    // No double-count: one log can't satisfy two scheduled days even with a wide grace.
    let wide = AdherenceCalculator.evaluate(schedule: .everyNDays(3), start: day(2026, 1, 1),
                                            end: day(2026, 1, 7), logDates: logs, graceDays: 6, calendar: cal)
    check(wide.takenCount == 1, "wide grace ⇒ one log still covers only one day")
    // On-time doses are never stolen to backfill a miss: Jan 2 & 3 logged, daily Jan 1-3,
    // grace 2 ⇒ Jan 1 stays missed (its neighbors' on-time logs aren't consumed for it).
    let protect = AdherenceCalculator.evaluate(schedule: .daily, start: day(2026, 1, 1),
                                               end: day(2026, 1, 3), logDates: [day(2026, 1, 2), day(2026, 1, 3)],
                                               graceDays: 2, calendar: cal)
    check(protect.missedDates == [day(2026, 1, 1)], "exact matches protect on-time doses from grace theft")
}

// MARK: - Streak
section("Streak calculator")
do {
    typealias E = StreakCalculator.DoseEvent
    func e(_ d: Int, _ taken: Bool) -> E { E(date: day(2026, 1, d), taken: taken) }

    check(StreakCalculator.compute(events: []) == .zero, "no events ⇒ zero")
    check(StreakCalculator.compute(events: [e(1, true), e(2, true), e(3, true)]) == .init(current: 3, longest: 3),
          "all taken ⇒ current 3, longest 3")
    check(StreakCalculator.compute(events: [e(1, true), e(2, false), e(3, true), e(4, true)]) == .init(current: 2, longest: 2),
          "miss in middle ⇒ current 2, longest 2")
    check(StreakCalculator.compute(events: [e(1, true), e(2, true), e(3, false)]) == .init(current: 0, longest: 2),
          "trailing miss ⇒ current 0, longest 2")
    // Unsorted input is sorted first; longest run is 1,2,3 (=3), current trailing from day 5 = 1.
    check(StreakCalculator.compute(events: [e(5, true), e(2, true), e(1, true), e(4, false), e(3, true)]) == .init(current: 1, longest: 3),
          "unsorted events sort chronologically")

    // events(from:) — a not-yet-taken dose scheduled TODAY is pending, never a miss.
    let logs = [1, 2, 3, 5, 6].map { day(2026, 1, $0) }        // Jan 4 & 7 not logged
    let r = AdherenceCalculator.evaluate(schedule: .daily, start: day(2026, 1, 1), end: day(2026, 1, 7), logDates: logs, calendar: cal)
    let pendingToday = StreakCalculator.events(from: r, asOf: day(2026, 1, 7), calendar: cal)
    check(pendingToday.count == 6, "today's un-taken dose excluded (6 past events, not 7)")
    check(StreakCalculator.compute(events: pendingToday) == .init(current: 2, longest: 3),
          "pending today ⇒ current 2 (Jan 5,6), longest 3 (Jan 1-3)")

    // Same schedule but today IS taken ⇒ today counts and extends the streak.
    let logs2 = [1, 2, 3, 5, 6, 7].map { day(2026, 1, $0) }
    let r2 = AdherenceCalculator.evaluate(schedule: .daily, start: day(2026, 1, 1), end: day(2026, 1, 7), logDates: logs2, calendar: cal)
    let takenToday = StreakCalculator.events(from: r2, asOf: day(2026, 1, 7), calendar: cal)
    check(takenToday.count == 7 && StreakCalculator.compute(events: takenToday) == .init(current: 3, longest: 3),
          "today taken ⇒ current 3 (Jan 5,6,7)")

    check(StreakCalculator.earnedMilestone(for: 6) == 0 && StreakCalculator.earnedMilestone(for: 7) == 7
          && StreakCalculator.earnedMilestone(for: 29) == 7 && StreakCalculator.earnedMilestone(for: 30) == 30
          && StreakCalculator.earnedMilestone(for: 100) == 90, "milestones 7/30/90")
}

// MARK: - Titration
section("Titration planner")
do {
    let steps: [TitrationPlanner.Step] = [
        .weeks(4, dose: .mg(0.25)), .weeks(4, dose: .mg(0.5)), .weeks(4, dose: .mg(1.0)),
    ]
    check(TitrationPlanner.totalDays(steps) == 84, "3×4-week steps ⇒ 84 days")
    let phases = TitrationPlanner.plan(steps: steps, startDate: day(2026, 1, 1), calendar: cal)
    check(phases.count == 3, "3 phases")
    check(phases[0].endDate == day(2026, 1, 29), "phase 0 ends 2026-01-29")
    check(TitrationPlanner.phase(on: day(2026, 1, 15), in: phases)?.dose == .mg(0.25), "Jan 15 ⇒ 0.25 mg")
    check(TitrationPlanner.phase(on: day(2026, 1, 29), in: phases)?.dose == .mg(0.5), "Jan 29 (boundary) ⇒ 0.5 mg")
}

// MARK: - Site rotation
section("Site rotation advisor")
do {
    let c = UUID()
    let recentAbdomen = [DoseLog(compoundID: c, timestamp: day(2026, 6, 30), dose: .mcg(250), site: .abdomenUpperLeft)]
    let next = SiteRotationAdvisor.suggestNext(history: recentAbdomen)
    check(next != nil && next?.region != .abdomen, "rotates away from just-used abdomen")
    check(SiteRotationAdvisor.suggestNext(history: []) != nil, "empty history still suggests a site")

    let history = [
        DoseLog(compoundID: c, timestamp: day(2026, 1, 1), dose: .mcg(250), site: .thighLeft),
        DoseLog(compoundID: c, timestamp: day(2026, 6, 1), dose: .mcg(250), site: .thighRight),
        DoseLog(compoundID: c, timestamp: day(2026, 6, 30), dose: .mcg(250), site: .abdomenUpperLeft),
    ]
    check(SiteRotationAdvisor.suggestNext(candidates: [.thighLeft, .thighRight], history: history) == .thighLeft,
          "picks less-recently-used thigh")
}

// MARK: - Blend calculator
section("Blend calculator")
do {
    // GLOW in 5 mL, draw 0.5 mL: GHK 5000 mcg, TB-500 1000 mcg, BPC-157 1000 mcg.
    let r = try BlendCalculator.dose(blend: BlendPresets.glow, solventVolumeMilliliters: 5, drawVolumeMilliliters: 0.5)
    check(approx(r.syringeUnits, 50), "0.5 mL ⇒ 50 units")
    let byName = Dictionary(uniqueKeysWithValues: r.components.map { ($0.name, $0.deliveredDose.micrograms) })
    check(approx(byName["GHK-Cu"] ?? -1, 5000), "GHK-Cu 50mg/5mL @0.5mL ⇒ 5000 mcg")
    check(approx(byName["TB-500"] ?? -1, 1000), "TB-500 10mg/5mL @0.5mL ⇒ 1000 mcg")
    check(approx(byName["BPC-157"] ?? -1, 1000), "BPC-157 10mg/5mL @0.5mL ⇒ 1000 mcg")

    // Wolverine 10+10 mg in 2 mL, draw by 20 units (=0.2 mL): 1000 mcg each.
    let w = try BlendCalculator.dose(blend: BlendPresets.wolverine, solventVolumeMilliliters: 2, syringeUnits: 20)
    check(approx(w.drawVolumeMilliliters, 0.2), "20 units ⇒ 0.2 mL")
    check(w.components.allSatisfy { approx($0.deliveredDose.micrograms, 1000) }, "Wolverine ⇒ 1000 mcg per component")
}
@MainActor func expectBlendThrow(_ label: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures += 1; print("  ✗ FAIL: \(label) (did not throw)") }
    catch is BlendError { print("  ✓ \(label)") }
    catch { failures += 1; print("  ✗ FAIL: \(label) (threw \(error))") }
}
expectBlendThrow("rejects empty blend") {
    _ = try BlendCalculator.dose(blend: Blend(name: "x", components: []), solventVolumeMilliliters: 2, drawVolumeMilliliters: 0.1)
}

// MARK: - Compounded-dose safety guard
section("Compounded-dose safety")
do {
    let compounded = Compound(name: "Compounded semaglutide", category: .glp1,
                              regulatoryStatus: .compoundedOnly, evidenceTier: .fdaApproved)
    // No concentration on file ⇒ unit dosing must be blocked.
    let noConc = Vial(compoundID: compounded.id, mass: .mg(5)) // not reconstituted
    check(CompoundedDoseSafety.mustBlockUnitDosing(compound: compounded, vial: noConc, entryMode: .syringeUnits),
          "compounded + unknown concentration + unit entry ⇒ BLOCK")
    check(CompoundedDoseSafety.advisories(compound: compounded, vial: noConc, entryMode: .syringeUnits).first?.severity == .block,
          "advisory severity is .block")
    // Concentration known ⇒ allowed (warning only).
    let withConc = Vial(compoundID: compounded.id, mass: .mg(5), solventVolumeMilliliters: 2)
    check(!CompoundedDoseSafety.mustBlockUnitDosing(compound: compounded, vial: withConc, entryMode: .syringeUnits),
          "compounded + known concentration ⇒ not blocked")
    // Mass entry is always fine, even without concentration.
    check(!CompoundedDoseSafety.mustBlockUnitDosing(compound: compounded, vial: noConc, entryMode: .mass),
          "mass entry never blocked")
    // FDA-approved branded product is unaffected.
    check(!CompoundedDoseSafety.mustBlockUnitDosing(compound: CompoundCatalog.tirzepatide, vial: noConc, entryMode: .syringeUnits),
          "branded FDA-approved product ⇒ not blocked")
    // Research compound surfaces the info disclaimer.
    check(CompoundedDoseSafety.advisories(compound: CompoundCatalog.bpc157, vial: nil, entryMode: .mass).contains { $0.severity == .info },
          "research compound ⇒ info disclaimer")
}

// MARK: - Catalog integrity
section("Compound catalog")
do {
    check(CompoundCatalog.all.count == 35, "catalog has 35 seeded compounds")
    check(Set(CompoundCatalog.all.map { $0.id }).count == CompoundCatalog.all.count, "catalog IDs are unique")
    check(CompoundCatalog.tesamorelin.evidenceTier == .fdaApproved && CompoundCatalog.tesamorelin.regulatoryStatus == .fdaApproved,
          "tesamorelin is the FDA-approved anchor")
    check(CompoundCatalog.bpc157.evidenceTier == .preclinicalOrFailed && CompoundCatalog.bpc157.requiresResearchDisclaimer,
          "BPC-157 is preclinical + needs disclaimer")
    check(CompoundCatalog.retatrutide.regulatoryStatus == .researchOnly, "retatrutide flagged investigational/research-only")
    check(TitrationTemplates.wegovy.steps.count == 5 && TitrationTemplates.wegovy.steps.last?.dose == .mg(2.4),
          "Wegovy ladder ends at 2.4 mg over 5 steps")
    check(TitrationTemplates.tirzepatide.initiationOnlyStepIndices.contains(0),
          "tirzepatide 2.5 mg flagged initiation-only")
}

// MARK: - Dosing from a known concentration (pre-mixed / pharmacy vials)
section("Dosing calculator (pre-mixed)")
do {
    // Compounded semaglutide 2.5 mg/mL, 0.25 mg dose ⇒ 0.10 mL, 10 units; 2 mL vial ⇒ 20 doses.
    let r = try DosingCalculator.draw(dose: .mg(0.25), concentration: .mgPerMl(2.5), totalVolumeMilliliters: 2)
    check(approx(r.drawVolumeMilliliters, 0.10), "2.5 mg/mL @ 0.25 mg ⇒ 0.10 mL")
    check(approx(r.syringeUnits, 10), "⇒ 10 units (U-100)")
    check(r.dosesPerVial == 20, "2 mL @ 0.25 mg ⇒ 20 doses")
    // mcg dosing on a research-peptide concentration.
    let r2 = try DosingCalculator.draw(dose: .mcg(500), concentration: .mgPerMl(5))
    check(approx(r2.syringeUnits, 10), "5 mg/mL @ 500 mcg ⇒ 10 units")
    check(r2.dosesPerVial == nil, "no total volume ⇒ doses/vial nil")
    // Concentration from mass + volume matches reconstitution.
    let c = Concentration(mass: .mg(5), inMilliliters: 2)
    check(approx(c.microgramsPerMilliliter, 2500), "Concentration(5mg in 2mL) == 2500 mcg/mL")
}
@MainActor func expectDosingThrow(_ expected: DosingError, _ label: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures += 1; print("  ✗ FAIL: \(label) (did not throw)") }
    catch let e as DosingError where e == expected { print("  ✓ \(label)") }
    catch { failures += 1; print("  ✗ FAIL: \(label) (threw \(error))") }
}
expectDosingThrow(.nonPositiveConcentration, "rejects zero concentration") {
    _ = try DosingCalculator.draw(dose: .mg(1), concentration: .mgPerMl(0))
}

// MARK: - News feed contract
section("News feed")
do {
    let feed = try NewsFeed.decodeSample()
    check(feed.items.count == 25, "sample feed decodes 25 items")
    check(feed.trending.first?.popularity == feed.items.map(\.popularity).max(), "trending sorted by popularity")
    check(!feed.items(mentioning: "Retatrutide").isEmpty, "can filter items by compound")
    check(feed.majorUpdates.count == 5, "5 items flagged as major updates")
    // Editorial contract — the transparency guarantees, enforced in code:
    check(feed.items.allSatisfy { !$0.sources.isEmpty }, "EVERY item carries ≥1 source citation")
    check(feed.items.allSatisfy { !$0.disclaimer.isEmpty }, "EVERY item carries a disclaimer")
    check(feed.items.allSatisfy { $0.sources.allSatisfy { !$0.url.isEmpty } }, "every source has a URL")
    check(feed.items.allSatisfy { $0.id.count > 0 }, "every item has a stable id")
    check(Set(feed.items.map(\.id)).count == feed.items.count, "item ids are unique")
    // Editorial: every item now ships a crafted, scannable teaser (drives list/card copy).
    check(feed.items.allSatisfy { $0.teaser != nil }, "EVERY item carries a teaser")
    check(feed.items.allSatisfy { ($0.teaser?.count ?? 0) <= 110 }, "every teaser is ≤110 chars")
    // The bundled sample omits imageURL app-wide (branded-gradient fallback is the premium look).
    check(feed.items.allSatisfy { $0.imageURL == nil }, "sample omits imageURL (uses gradient fallback)")

    // Optional imageURL still round-trips when a live feed DOES provide one.
    let imgJSON = #"{"id":"i1","headline":"H","summary":"S","category":"General","compounds":[],"sources":[{"name":"n","url":"https://example.com","kind":"news"}],"publishedAt":"2026-07-08T00:00:00Z","popularity":0,"isMajorUpdate":false,"disclaimer":"d","imageURL":"https://example.com/x.jpg"}"#
    let withImg = try JSONDecoder().decode(NewsItem.self, from: Data(imgJSON.utf8))
    check(withImg.imageURL == "https://example.com/x.jpg", "optional imageURL decodes when present")

    // teaser / listText — additive optional; teaser-less items fall back to summary via listText.
    let withTeaser = NewsItem(
        id: "t1", headline: "H", summary: "Full summary body.", category: .general,
        compounds: [], sources: [], publishedAt: "2026-07-08T00:00:00Z",
        popularity: 0, isMajorUpdate: false, disclaimer: "d", teaser: "Short teaser.")
    check(withTeaser.listText == (withTeaser.teaser ?? withTeaser.summary) && withTeaser.listText == "Short teaser.",
          "listText == teaser when teaser present")
    let noTeaser = NewsItem(
        id: "t2", headline: "H", summary: "Full summary body.", category: .general,
        compounds: [], sources: [], publishedAt: "2026-07-08T00:00:00Z",
        popularity: 0, isMajorUpdate: false, disclaimer: "d")
    check(noTeaser.teaser == nil && noTeaser.listText == noTeaser.summary,
          "listText == summary when teaser nil (backward-compatible fallback)")
} catch {
    check(false, "news feed failed to decode: \(error)")
}

// MARK: - Subjective metric quick-reports
section("Subjective metric quick-reports")
do {
    check(SubjectiveMetric.quickReports(energy: nil, sideEffectSeverity: nil).isEmpty,
          "both nil ⇒ no metrics")

    let energyOnly = SubjectiveMetric.quickReports(energy: 7, sideEffectSeverity: nil)
    check(energyOnly.count == 1 && energyOnly.first?.name == SubjectiveMetric.energyName,
          "energy only ⇒ 1 metric named \"\(SubjectiveMetric.energyName)\"")

    let sideOnly = SubjectiveMetric.quickReports(energy: nil, sideEffectSeverity: 3)
    check(sideOnly.count == 1 && sideOnly.first?.name == SubjectiveMetric.sideEffectName,
          "side-effect only ⇒ 1 metric named \"\(SubjectiveMetric.sideEffectName)\"")

    let both = SubjectiveMetric.quickReports(energy: 5, sideEffectSeverity: 2)
    check(both.count == 2, "both non-nil ⇒ 2 metrics")
    check(both.map(\.name) == [SubjectiveMetric.energyName, SubjectiveMetric.sideEffectName],
          "metrics ordered energy then side-effects")

    let clamped = SubjectiveMetric.quickReports(energy: 12, sideEffectSeverity: -4)
    check(approx(clamped[0].value, 10), "energy 12 clamps to 10")
    check(approx(clamped[1].value, 0), "side-effect -4 clamps to 0")
}

// MARK: - CompoundCategory display/storage decoupling
section("CompoundCategory display name")
do {
    check(CompoundCategory.allCases.count == 6, "6 categories (count unchanged)")
    check(CompoundCategory.allCases.allSatisfy { !$0.displayName.isEmpty },
          "every category has a non-empty displayName")
    // rawValues are now frozen stable storage keys — assert they are unchanged.
    check(CompoundCategory.glp1.rawValue == "GLP-1 / incretin", "glp1 rawValue is stable")
    check(CompoundCategory.blend.rawValue == "Blend", "blend rawValue is stable")
    // Today displayName mirrors rawValue verbatim (decoupled, not yet diverged).
    check(CompoundCategory.allCases.allSatisfy { $0.displayName == $0.rawValue },
          "displayName currently matches rawValue for every case")
}

// MARK: - DoseDrawResult protocol
section("DoseDrawResult protocol")
do {
    // Same physical scenario via both paths: 5 mg vial in 2 mL ⇒ 2500 mcg/mL; 250 mcg dose.
    let recon = try ReconstitutionCalculator.calculate(
        ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(250)))
    let prepared = try DosingCalculator.draw(
        dose: .mcg(250), concentration: .mgPerMl(2.5), totalVolumeMilliliters: 2)

    let a: any DoseDrawResult = recon
    let b: any DoseDrawResult = prepared
    check(approx(a.syringeUnits, b.syringeUnits), "both results agree on syringeUnits (10)")
    check(approx(a.drawVolumeMilliliters, b.drawVolumeMilliliters), "both agree on draw volume (0.10 mL)")
    check(approx(a.concentrationMcgPerMl, b.concentrationMcgPerMl), "both agree on concentration (2500)")
    check(a.exactDosesPerVialOrNil != nil && approx(a.exactDosesPerVialOrNil ?? -1, 20),
          "reconstitution exposes exactDosesPerVialOrNil == 20")
    check(b.exactDosesPerVialOrNil != nil && approx(b.exactDosesPerVialOrNil ?? -1, 20),
          "prepared (with total volume) exposes exactDosesPerVialOrNil == 20")

    // No total volume ⇒ prepared result's exactDosesPerVialOrNil is nil.
    let noTotal: any DoseDrawResult = try DosingCalculator.draw(dose: .mcg(500), concentration: .mgPerMl(5))
    check(noTotal.exactDosesPerVialOrNil == nil, "prepared without total volume ⇒ exactDosesPerVialOrNil nil")
} catch {
    check(false, "DoseDrawResult section threw: \(error)")
}

// MARK: - Summary
print("\n\(failures == 0 ? "✅ PASS" : "❌ FAIL") — \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
