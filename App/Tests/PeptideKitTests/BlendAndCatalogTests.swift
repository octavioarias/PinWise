import Testing
import Foundation
@testable import PeptideKit

@Suite("Blend calculator")
struct BlendCalculatorTests {
    @Test func glowFromVolume() throws {
        let r = try BlendCalculator.dose(blend: BlendPresets.glow, solventVolumeMilliliters: 5, drawVolumeMilliliters: 0.5)
        #expect(abs(r.syringeUnits - 50) < 1e-9)
        let byName = Dictionary(uniqueKeysWithValues: r.components.map { ($0.name, $0.deliveredDose.micrograms) })
        #expect(abs((byName["GHK-Cu"] ?? -1) - 5000) < 1e-9)
        #expect(abs((byName["TB-500"] ?? -1) - 1000) < 1e-9)
        #expect(abs((byName["BPC-157"] ?? -1) - 1000) < 1e-9)
    }

    @Test func wolverineFromUnits() throws {
        let w = try BlendCalculator.dose(blend: BlendPresets.wolverine, solventVolumeMilliliters: 2, syringeUnits: 20)
        #expect(abs(w.drawVolumeMilliliters - 0.2) < 1e-9)
        #expect(w.components.allSatisfy { abs($0.deliveredDose.micrograms - 1000) < 1e-9 })
    }

    @Test func rejectsEmptyBlend() {
        #expect(throws: BlendError.emptyBlend) {
            try BlendCalculator.dose(blend: Blend(name: "x", components: []), solventVolumeMilliliters: 2, drawVolumeMilliliters: 0.1)
        }
    }
}

@Suite("Compounded-dose safety")
struct CompoundedDoseSafetyTests {
    private let compounded = Compound(name: "Compounded semaglutide", category: .glp1,
                                      regulatoryStatus: .compoundedOnly, evidenceTier: .fdaApproved)

    @Test func blocksUnitDosingWithoutConcentration() {
        let noConc = Vial(compoundID: compounded.id, mass: .mg(5))
        #expect(CompoundedDoseSafety.mustBlockUnitDosing(compound: compounded, vial: noConc, entryMode: .syringeUnits))
        #expect(CompoundedDoseSafety.advisories(compound: compounded, vial: noConc, entryMode: .syringeUnits).first?.severity == .block)
    }

    @Test func allowsWhenConcentrationKnown() {
        let withConc = Vial(compoundID: compounded.id, mass: .mg(5), solventVolumeMilliliters: 2)
        #expect(!CompoundedDoseSafety.mustBlockUnitDosing(compound: compounded, vial: withConc, entryMode: .syringeUnits))
    }

    @Test func massEntryNeverBlocked() {
        let noConc = Vial(compoundID: compounded.id, mass: .mg(5))
        #expect(!CompoundedDoseSafety.mustBlockUnitDosing(compound: compounded, vial: noConc, entryMode: .mass))
    }

    @Test func brandedProductUnaffected() {
        let noConc = Vial(compoundID: CompoundCatalog.tirzepatide.id, mass: .mg(5))
        #expect(!CompoundedDoseSafety.mustBlockUnitDosing(compound: CompoundCatalog.tirzepatide, vial: noConc, entryMode: .syringeUnits))
    }
}

@Suite("Compound catalog")
struct CompoundCatalogTests {
    @Test func integrity() {
        #expect(CompoundCatalog.all.count == 35)
        #expect(Set(CompoundCatalog.all.map { $0.id }).count == CompoundCatalog.all.count)
    }

    @Test func evidenceTiers() {
        #expect(CompoundCatalog.tesamorelin.evidenceTier == .fdaApproved)
        #expect(CompoundCatalog.bpc157.evidenceTier == .preclinicalOrFailed)
        #expect(CompoundCatalog.bpc157.requiresResearchDisclaimer)
        #expect(CompoundCatalog.retatrutide.regulatoryStatus == .researchOnly)
    }

    @Test func titrationLadders() {
        #expect(TitrationTemplates.wegovy.steps.count == 5)
        #expect(TitrationTemplates.wegovy.steps.last?.dose == .mg(2.4))
        #expect(TitrationTemplates.tirzepatide.initiationOnlyStepIndices.contains(0))
    }
}
