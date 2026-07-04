import Testing
import Foundation
@testable import PeptideKit

private let tol = 1e-9

@Suite("Reconstitution calculator")
struct ReconstitutionCalculatorTests {

    // Canonical worked example: 5 mg vial + 2 mL water, 250 mcg dose.
    @Test func canonicalExample() throws {
        let r = try ReconstitutionCalculator.calculate(
            ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(250))
        )
        #expect(abs(r.concentrationMcgPerMl - 2500) < tol)
        #expect(abs(r.concentrationMgPerMl - 2.5) < tol)
        #expect(abs(r.drawVolumeMilliliters - 0.10) < tol)
        #expect(abs(r.syringeUnits - 10) < tol)
        #expect(r.dosesPerVial == 20)
        #expect(abs(r.exactDosesPerVial - 20) < tol)
    }

    // GLP-1 style: 10 mg tirzepatide + 1 mL, 2.5 mg dose ⇒ 25 units, 4 doses.
    @Test func tirzepatideExample() throws {
        let r = try ReconstitutionCalculator.calculate(
            ReconstitutionInput(vialMass: .mg(10), solventVolumeMilliliters: 1, desiredDose: .mg(2.5))
        )
        #expect(abs(r.concentrationMcgPerMl - 10_000) < tol)
        #expect(abs(r.drawVolumeMilliliters - 0.25) < tol)
        #expect(abs(r.syringeUnits - 25) < tol)
        #expect(r.dosesPerVial == 4)
    }

    // Non-U-100 syringe scaling: same 0.1 mL draw reads 4 units on a U-40 barrel.
    @Test func u40Syringe() throws {
        let r = try ReconstitutionCalculator.calculate(
            ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(250), syringe: .u40)
        )
        #expect(abs(r.syringeUnits - 4) < tol)
    }

    @Test func fractionalDosesPerVial() throws {
        let r = try ReconstitutionCalculator.calculate(
            ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mcg(300))
        )
        #expect(abs(r.exactDosesPerVial - (5000.0 / 300.0)) < tol)
        #expect(r.dosesPerVial == 16) // floor(16.66)
    }

    @Test func inverseDoseFromUnits() throws {
        let dose = try ReconstitutionCalculator.dose(forUnits: 10, vialMass: .mg(5), solventVolumeMilliliters: 2)
        #expect(abs(dose.micrograms - 250) < 1e-6)
    }

    @Test func roundTripUnitsToDose() throws {
        let r = try ReconstitutionCalculator.calculate(
            ReconstitutionInput(vialMass: .mg(10), solventVolumeMilliliters: 2, desiredDose: .mcg(500))
        )
        let back = try ReconstitutionCalculator.dose(forUnits: r.syringeUnits, vialMass: .mg(10), solventVolumeMilliliters: 2)
        #expect(abs(back.micrograms - 500) < 1e-6)
    }

    @Test func rejectsNonPositiveVialMass() {
        #expect(throws: ReconstitutionError.nonPositiveVialMass) {
            try ReconstitutionCalculator.calculate(
                ReconstitutionInput(vialMass: .mg(0), solventVolumeMilliliters: 2, desiredDose: .mcg(250)))
        }
    }

    @Test func rejectsNonPositiveSolvent() {
        #expect(throws: ReconstitutionError.nonPositiveSolventVolume) {
            try ReconstitutionCalculator.calculate(
                ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 0, desiredDose: .mcg(250)))
        }
    }

    @Test func rejectsDoseExceedingVial() {
        #expect(throws: ReconstitutionError.doseExceedsVialContents) {
            try ReconstitutionCalculator.calculate(
                ReconstitutionInput(vialMass: .mg(5), solventVolumeMilliliters: 2, desiredDose: .mg(6)))
        }
    }
}
