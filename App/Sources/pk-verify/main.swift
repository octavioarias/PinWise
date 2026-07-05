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
    check(feed.items.count == 4, "sample feed decodes 4 items")
    check(feed.trending.first?.popularity == feed.items.map(\.popularity).max(), "trending sorted by popularity")
    check(!feed.items(mentioning: "Retatrutide").isEmpty, "can filter items by compound")
    check(feed.majorUpdates.count == 2, "2 items flagged as major updates")
    // Editorial contract — the transparency guarantees, enforced in code:
    check(feed.items.allSatisfy { !$0.sources.isEmpty }, "EVERY item carries ≥1 source citation")
    check(feed.items.allSatisfy { !$0.disclaimer.isEmpty }, "EVERY item carries a disclaimer")
    check(feed.items.allSatisfy { $0.sources.allSatisfy { !$0.url.isEmpty } }, "every source has a URL")
    check(feed.items.filter { $0.imageURL != nil }.count == 1, "optional imageURL decodes both when present and absent")
} catch {
    check(false, "news feed failed to decode: \(error)")
}

// MARK: - Summary
print("\n\(failures == 0 ? "✅ PASS" : "❌ FAIL") — \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
