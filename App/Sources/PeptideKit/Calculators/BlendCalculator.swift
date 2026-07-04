import Foundation

public enum BlendError: Error, Equatable, Sendable {
    case emptyBlend
    case nonPositiveSolventVolume
    case nonPositiveDraw
}

/// The per-component amount delivered by a single injection from a blend vial.
public struct BlendComponentDose: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public let name: String
    public let concentrationMcgPerMl: Double
    public let deliveredDose: Mass
}

public struct BlendDoseResult: Codable, Hashable, Sendable {
    public let drawVolumeMilliliters: Double
    public let syringeUnits: Double
    public let components: [BlendComponentDose]
}

/// Computes the dose of every component delivered by one injection from a blend vial.
///
/// Because all components share the same vial and the same reconstitution volume, one
/// injection volume `v` (mL) delivers, for each component of mass `Mᵢ`:
///   - concentrationᵢ = `Mᵢ / solventVolume`  (µg/mL)
///   - doseᵢ = `concentrationᵢ × v`  (µg)
///
/// ### Example — "GLOW" (GHK-Cu 50 mg + TB-500 10 mg + BPC-157 10 mg) in 5 mL, drawing 0.5 mL:
///   GHK-Cu 10000 µg/mL × 0.5 = 5000 µg; TB-500 & BPC-157 2000 µg/mL × 0.5 = 1000 µg each.
public enum BlendCalculator {

    /// Dose from an explicit draw volume (mL).
    public static func dose(
        blend: Blend,
        solventVolumeMilliliters: Double,
        drawVolumeMilliliters: Double,
        syringe: SyringeScale = .u100
    ) throws -> BlendDoseResult {
        guard !blend.components.isEmpty else { throw BlendError.emptyBlend }
        guard solventVolumeMilliliters > 0 else { throw BlendError.nonPositiveSolventVolume }
        guard drawVolumeMilliliters > 0 else { throw BlendError.nonPositiveDraw }

        let comps = blend.components.map { c -> BlendComponentDose in
            let conc = c.massPerVial.micrograms / solventVolumeMilliliters
            return BlendComponentDose(
                id: c.id,
                name: c.name,
                concentrationMcgPerMl: conc,
                deliveredDose: Mass(micrograms: conc * drawVolumeMilliliters)
            )
        }
        return BlendDoseResult(
            drawVolumeMilliliters: drawVolumeMilliliters,
            syringeUnits: drawVolumeMilliliters * syringe.unitsPerMilliliter,
            components: comps
        )
    }

    /// Dose from a syringe-unit reading instead of a volume.
    public static func dose(
        blend: Blend,
        solventVolumeMilliliters: Double,
        syringeUnits: Double,
        syringe: SyringeScale = .u100
    ) throws -> BlendDoseResult {
        guard syringeUnits > 0 else { throw BlendError.nonPositiveDraw }
        let volume = syringeUnits / syringe.unitsPerMilliliter
        return try dose(
            blend: blend,
            solventVolumeMilliliters: solventVolumeMilliliters,
            drawVolumeMilliliters: volume,
            syringe: syringe
        )
    }
}
