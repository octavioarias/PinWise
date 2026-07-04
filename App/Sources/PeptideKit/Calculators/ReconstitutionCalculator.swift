import Foundation

/// Errors surfaced by ``ReconstitutionCalculator``.
public enum ReconstitutionError: Error, Equatable, Sendable {
    case nonPositiveVialMass
    case nonPositiveSolventVolume
    case nonPositiveDose
    case doseExceedsVialContents
}

/// The user-supplied inputs for a reconstitution calculation.
public struct ReconstitutionInput: Codable, Hashable, Sendable {
    /// Total peptide mass contained in the (lyophilized) vial.
    public var vialMass: Mass
    /// Volume of bacteriostatic / sterile water added to the vial, in milliliters.
    public var solventVolumeMilliliters: Double
    /// The per-injection dose the user wants to draw.
    public var desiredDose: Mass
    /// Which insulin-syringe scale the user injects with.
    public var syringe: SyringeScale

    public init(
        vialMass: Mass,
        solventVolumeMilliliters: Double,
        desiredDose: Mass,
        syringe: SyringeScale = .u100
    ) {
        self.vialMass = vialMass
        self.solventVolumeMilliliters = solventVolumeMilliliters
        self.desiredDose = desiredDose
        self.syringe = syringe
    }
}

/// The full set of derived values a user needs to draw and dose accurately.
public struct ReconstitutionResult: Codable, Hashable, Sendable {
    /// Resulting solution strength in micrograms per milliliter.
    public let concentrationMcgPerMl: Double
    /// Same strength expressed in milligrams per milliliter.
    public let concentrationMgPerMl: Double
    /// Volume to draw for one dose, in milliliters.
    public let drawVolumeMilliliters: Double
    /// The mark to draw to on the insulin syringe (e.g. "10 units").
    public let syringeUnits: Double
    /// Whole doses obtainable from the vial at this dose.
    public let dosesPerVial: Int
    /// Exact (fractional) doses per vial, before flooring — useful for cost-per-dose.
    public let exactDosesPerVial: Double
}

/// Computes reconstitution math for lyophilized peptides.
///
/// ## The formula
/// Given a vial containing `M` micrograms of peptide reconstituted with `V` mL of water,
/// the concentration is `C = M / V` (µg/mL). To deliver a dose `D` (µg):
///
///   - draw volume  = `D / C`  (mL)
///   - syringe units = `drawVolume × unitsPerMl`  (U-100 ⇒ ×100)
///   - doses/vial    = `M / D`
///
/// ### Worked example
/// A 5 mg vial + 2 mL water ⇒ `C = 5000 µg / 2 mL = 2500 µg/mL`.
/// A 250 µg dose ⇒ draw `250 / 2500 = 0.10 mL` ⇒ `0.10 × 100 = 10 units` on a U-100 syringe,
/// and `5000 / 250 = 20` doses per vial.
public enum ReconstitutionCalculator {
    public static func calculate(_ input: ReconstitutionInput) throws -> ReconstitutionResult {
        guard input.vialMass.micrograms > 0 else { throw ReconstitutionError.nonPositiveVialMass }
        guard input.solventVolumeMilliliters > 0 else { throw ReconstitutionError.nonPositiveSolventVolume }
        guard input.desiredDose.micrograms > 0 else { throw ReconstitutionError.nonPositiveDose }
        guard input.desiredDose.micrograms <= input.vialMass.micrograms else {
            throw ReconstitutionError.doseExceedsVialContents
        }

        let concMcgPerMl = input.vialMass.micrograms / input.solventVolumeMilliliters
        let drawVolume = input.desiredDose.micrograms / concMcgPerMl
        let units = drawVolume * input.syringe.unitsPerMilliliter
        let exactDoses = input.vialMass.micrograms / input.desiredDose.micrograms

        return ReconstitutionResult(
            concentrationMcgPerMl: concMcgPerMl,
            concentrationMgPerMl: concMcgPerMl / 1_000,
            drawVolumeMilliliters: drawVolume,
            syringeUnits: units,
            dosesPerVial: Int(exactDoses.rounded(.down)),
            exactDosesPerVial: exactDoses
        )
    }

    /// Inverse helper: given a target draw in syringe units, what dose does that deliver?
    /// Useful for the "I drew to 12 units — how much did I take?" flow.
    public static func dose(
        forUnits units: Double,
        vialMass: Mass,
        solventVolumeMilliliters: Double,
        syringe: SyringeScale = .u100
    ) throws -> Mass {
        guard vialMass.micrograms > 0 else { throw ReconstitutionError.nonPositiveVialMass }
        guard solventVolumeMilliliters > 0 else { throw ReconstitutionError.nonPositiveSolventVolume }
        guard units > 0 else { throw ReconstitutionError.nonPositiveDose }
        let concMcgPerMl = vialMass.micrograms / solventVolumeMilliliters
        let volume = units / syringe.unitsPerMilliliter
        return Mass(micrograms: concMcgPerMl * volume)
    }
}
