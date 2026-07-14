import Foundation

public enum DosingError: Error, Equatable, Sendable {
    case nonPositiveConcentration
    case nonPositiveDose
    case nonPositiveVolume
}

/// The values needed to draw a dose from an already-known concentration.
public struct PreparedDoseResult: Codable, Hashable, Sendable {
    public let concentrationMcgPerMl: Double
    public let concentrationMgPerMl: Double
    public let drawVolumeMilliliters: Double
    public let syringeUnits: Double
    /// Whole doses in the vial, when a total volume is provided.
    public let dosesPerVial: Int?
    public let exactDosesPerVial: Double?
}

extension PreparedDoseResult: DoseDrawResult {
    /// Only derivable when a total volume was supplied; otherwise `nil`.
    public var exactDosesPerVialOrNil: Double? { exactDosesPerVial }
}

/// Dosing math for **pre-mixed / ready-to-use** products (e.g. compounded-pharmacy vials
/// labeled in mg/mL) — no reconstitution needed. Complements ``ReconstitutionCalculator``,
/// which derives the concentration from powder + water; here the concentration is given.
///
/// ### Example — compounded semaglutide 2.5 mg/mL, 0.25 mg dose:
///   volume = 250 µg / 2500 µg·mL⁻¹ = 0.10 mL ⇒ 10 units (U-100).
public enum DosingCalculator {
    public static func draw(
        dose: Mass,
        concentration: Concentration,
        totalVolumeMilliliters: Double? = nil,
        syringe: SyringeScale = .u100
    ) throws -> PreparedDoseResult {
        guard concentration.microgramsPerMilliliter > 0 else { throw DosingError.nonPositiveConcentration }
        guard dose.micrograms > 0 else { throw DosingError.nonPositiveDose }

        let conc = concentration.microgramsPerMilliliter
        let volume = dose.micrograms / conc
        let units = volume * syringe.unitsPerMilliliter

        var whole: Int?
        var exact: Double?
        if let total = totalVolumeMilliliters {
            guard total > 0 else { throw DosingError.nonPositiveVolume }
            let e = (conc * total) / dose.micrograms
            exact = e
            whole = Int(e.rounded(.down))
        }

        return PreparedDoseResult(
            concentrationMcgPerMl: conc,
            concentrationMgPerMl: conc / 1_000,
            drawVolumeMilliliters: volume,
            syringeUnits: units,
            dosesPerVial: whole,
            exactDosesPerVial: exact
        )
    }
}
