import Foundation

/// How the user is entering a dose. Unit/volume entry is only safe once the product's
/// concentration is known.
public enum DoseEntryMode: String, Codable, Sendable {
    case mass          // e.g. "250 mcg" or "2.5 mg" — unambiguous
    case syringeUnits  // e.g. "draw to 20 units" — meaningless without concentration
    case volume        // e.g. "0.2 mL" — meaningless without concentration
}

/// Guards against the FDA-documented compounded-GLP-1 overdose pattern.
///
/// Compounded products come in **non-standardized** concentrations, and patients/providers
/// who dose by "units" or volume without pinning down mg/mL have self-administered
/// 5–20× the intended dose (FDA alert, July 29 2024; overdose counts come from
/// poison-center surveillance, not an FDA tally). The rule enforced here: for a
/// compounded product, unit/volume dosing is **blocked** until an explicit concentration
/// is on record; mass entry is always allowed.
public enum CompoundedDoseSafety {

    public struct Advisory: Codable, Hashable, Sendable {
        public enum Severity: String, Codable, Sendable { case info, warning, block }
        public let severity: Severity
        public let message: String
    }

    /// Whether unit/volume dosing must be blocked for this product + vial combination.
    public static func mustBlockUnitDosing(compound: Compound, vial: Vial?, entryMode: DoseEntryMode) -> Bool {
        guard compound.regulatoryStatus == .compoundedOnly else { return false }
        guard entryMode == .syringeUnits || entryMode == .volume else { return false }
        return (vial?.concentrationMcgPerMl ?? 0) <= 0
    }

    /// Advisories to surface for a dose-entry attempt, most severe first.
    public static func advisories(compound: Compound, vial: Vial?, entryMode: DoseEntryMode) -> [Advisory] {
        var out: [Advisory] = []

        if mustBlockUnitDosing(compound: compound, vial: vial, entryMode: entryMode) {
            out.append(Advisory(
                severity: .block,
                message: """
                Enter this product's concentration (mg/mL) before dosing by units or volume. \
                Compounded products are not standardized — dosing by units without the \
                concentration has caused 5–20× overdoses (FDA alert, 2024).
                """
            ))
        } else if compound.regulatoryStatus == .compoundedOnly {
            out.append(Advisory(
                severity: .warning,
                message: "Compounded product — confirm the strength printed on the label; concentrations vary by pharmacy and batch."
            ))
        }

        if compound.evidenceTier.needsStrongDisclaimer || compound.regulatoryStatus == .researchOnly {
            out.append(Advisory(severity: .info, message: Disclaimer.researchCompound))
        }

        return out
    }
}
